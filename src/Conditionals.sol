// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IIntake, IIntakePrice} from "./interfaces/IIntake.sol";
import {IOracleAttestation} from "./interfaces/IOracleAttestation.sol";

/// @title Conditionals
/// @notice Conditional prediction markets in IMD, settled by the IdentityMD oracle.
///
/// A market asks "if CONDITION, will OUTCOME?" and has two worlds:
///   world 0, the condition happens; world 1, it does not.
/// Each world has a YES and a NO pool for the outcome. Traders stake IMD in any of the four pools until `closeTime`.
///
/// After `resolveTime` anyone calls `requestResolution`. The contract pays the IdentityMD Intake for two oracle
/// questions (the condition and the outcome) out of the budget the creator deposited, and pins the hash of each
/// question it asked. An answer counts only when the oracle's signer signed it for this contract, for that exact
/// question, with at least the market's panel and quorum.
///
/// Settlement needs both answers. The condition's answer picks the world that happened; the outcome's answer picks
/// the winning side in it, in either world. The world that did not happen is refunded in full. In the world that
/// happened, the winning side splits the pot minus a 3% fee: 2% is burned (sent to 0x...dEaD) and 1% goes to the fee
/// recipient; the fee is capped at what the losing side staked, so a winner never nets less than they staked. A world
/// with stakes on only one side has no counterparty and is refunded with no fee. A market with no
/// usable answer by `voidAfter` (resolveTime + 30 days) can be voided by anyone, which refunds every stake; a void
/// waits while an ask younger than RETRY_DELAY is still live, so an answer on its way cannot be voided away.
///
/// The owner can only rotate the oracle configuration for future markets (behind a 3 day delay) and change the fee
/// recipient. It cannot touch stakes, answers or open markets: each market keeps the configuration it was created with.
contract Conditionals is Ownable2Step, ReentrancyGuard, EIP712, IOracleAttestation {
    using SafeERC20 for IERC20;
    using Strings for uint256;
    using Strings for address;

    // ---------------------------------------------------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------------------------------------------------

    /// @notice Where burned IMD goes. IMD reverts on transfers to the zero address.
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    uint256 public constant BPS = 10_000;
    /// @notice Total fee on a settled world's pot.
    uint256 public constant FEE_BPS = 300;
    /// @notice Burned share of the pot (2%).
    uint256 public constant BURN_BPS = 200;
    /// @notice Fee recipient's share of the pot (1%).
    uint256 public constant BUILDER_BPS = 100;

    /// @notice Smallest stake, 0.001 IMD.
    uint256 public constant MIN_STAKE = 1e15;

    uint256 public constant MAX_CONDITION_LENGTH = 280;
    uint256 public constant MAX_OUTCOME_LENGTH = 280;
    uint256 public constant MAX_RULES_LENGTH = 500;

    /// @notice Furthest a market's resolveTime can be from its creation.
    uint256 public constant MAX_HORIZON = 730 days;
    /// @notice How long after resolveTime a market waits for answers before anyone can void it.
    uint256 public constant RESOLUTION_PERIOD = 30 days;
    /// @notice How long an unanswered question waits before it can be asked again.
    uint256 public constant RETRY_DELAY = 1 days;
    /// @notice Delay before a proposed oracle configuration can be activated.
    uint256 public constant CONFIG_DELAY = 3 days;
    /// @notice How long after its delay a proposed configuration stays activatable. A proposal that is not
    ///         activated in this window lapses, so a creator never meets a configuration proposed months earlier.
    uint256 public constant CONFIG_WINDOW = 7 days;
    /// @notice How far ahead of this chain's clock an attestation's `issuedAt` may sit (the protocol's tolerance).
    uint256 public constant ISSUED_AT_TOLERANCE = 5 minutes;

    /// @notice Bounds for the oracle configuration.
    uint16 public constant MIN_PANEL_SIZE = 5;
    uint16 public constant MAX_PANEL_SIZE = 100;
    uint256 public constant MAX_PRICE = 10 ether;

    /// @notice The chain the oracle question's window is pinned to. On Robinhood Chain `block.number` is the
    ///         Ethereum mainnet block number, so the window is an Ethereum block.
    uint256 public constant QUESTION_CHAIN_ID = 1;
    /// @notice How far behind `block.number` the question's block is: the oracle needs at least 5 blocks of depth.
    uint256 public constant WINDOW_DEPTH = 10;
    /// @notice How long a signed answer stays valid.
    uint256 public constant VALID_FOR_SECONDS = 86_400;

    /// @notice The oracle action the contract is deployed with. Each market carries its own (`OracleConfig.action`),
    ///         so a new action version can be rotated in for future markets without a redeploy.
    bytes32 public constant ORACLE_ACTION = "oracle.request@oracle-1";

    bytes32 public constant ATTESTATION_TYPEHASH = keccak256(
        "OracleAttestation(bytes32 requestId,uint256 chainId,bytes32 questionHash,uint8 answerType,bytes answer,"
        "uint256 figure,uint64 fromBlock,uint64 toBlock,bytes32 blockHash,bytes32 panelJobId,uint16 panelSize,"
        "uint16 quorum,uint16 agreed,uint64 issuedAt,uint64 expiresAt)"
    );

    uint8 public constant CONDITION = 0;
    uint8 public constant OUTCOME = 1;

    uint8 public constant WORLD_HAPPENS = 0;
    uint8 public constant WORLD_DOES_NOT = 1;

    uint8 public constant YES = 0;
    uint8 public constant NO = 1;

    /// @dev Answer states.
    uint8 internal constant UNANSWERED = 0;
    uint8 internal constant ANSWER_TRUE = 1;
    uint8 internal constant ANSWER_FALSE = 2;

    // ---------------------------------------------------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------------------------------------------------

    enum Status {
        Open,
        Settled,
        Voided
    }

    struct OracleConfig {
        IIntake intake;
        /// @dev The attester: an EOA, or a contract that answers ERC-1271 (the protocol's signer registry).
        address signer;
        uint128 price;
        uint16 panelSize;
        uint16 quorum;
        /// @dev The Intake action id, e.g. bytes32("oracle.request@oracle-1").
        bytes32 action;
    }

    struct Market {
        address creator;
        uint64 closeTime;
        uint64 resolveTime;
        uint64 voidAfter;
        Status status;
        /// @dev Set on settlement: the world that happened, the winning side in it, and whether it was refunded.
        uint8 world;
        uint8 winningSide;
        bool worldRefunded;
        /// @dev Per question: UNANSWERED, ANSWER_TRUE or ANSWER_FALSE.
        uint8[2] answers;
        /// @dev Per question: asks sent and not yet called back, and when the last one was sent.
        uint8[2] openAsks;
        uint64[2] lastAskAt;
        /// @dev The oracle configuration this market was created with.
        OracleConfig oracle;
        /// @dev IMD left for oracle questions, deposited by the creator.
        uint256 budget;
        /// @dev pools[world][side].
        uint256[2][2] pools;
        /// @dev Pot of the settled world after fees.
        uint256 netPot;
        string condition;
        string outcome;
        string rules;
    }

    struct Ask {
        uint256 marketId;
        uint8 question;
        bool live;
        bytes32 questionHash;
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------------------------------------------------

    IERC20 public immutable imd;

    /// @notice The configuration new markets are created with.
    OracleConfig public oracleConfig;
    /// @notice A proposed configuration and when it can be activated (zero: none).
    OracleConfig public pendingOracleConfig;
    uint256 public pendingOracleConfigAt;

    /// @notice Receives the 1% fee.
    address public feeRecipient;

    uint256 public marketCount;
    mapping(uint256 => Market) internal _markets;

    /// @notice stakes[marketId][trader][world][side].
    mapping(uint256 => mapping(address => uint256[2][2])) internal _stakes;
    mapping(uint256 => mapping(address => bool)) public claimed;

    /// @notice Asks this contract sent, keyed by keccak256(intake, intake requestId).
    mapping(bytes32 => Ask) public asks;

    /// @notice IMD a settlement or void could not push to a third party (IMD refused the transfer), collectable
    ///         by that party with `withdrawOwed`.
    mapping(address => uint256) public owed;

    /// @notice Totals, for display.
    uint256 public totalBurned;
    uint256 public totalBuilderFees;
    uint256 public totalOracleSpend;

    // ---------------------------------------------------------------------------------------------------------------
    // Events and errors
    // ---------------------------------------------------------------------------------------------------------------

    event MarketCreated(
        uint256 indexed marketId,
        address indexed creator,
        uint64 closeTime,
        uint64 resolveTime,
        string condition,
        string outcome,
        string rules
    );
    event Staked(uint256 indexed marketId, address indexed trader, uint8 world, uint8 side, uint256 amount);
    event ResolutionRequested(
        uint256 indexed marketId, uint8 indexed question, bytes32 requestId, bytes32 questionHash, uint256 windowBlock
    );
    event Answered(uint256 indexed marketId, uint8 indexed question, bool answer, bytes32 oracleRequestId);
    event AnswerIgnored(uint256 indexed marketId, uint8 indexed question, bytes32 requestId);
    event AskFailed(uint256 indexed marketId, uint8 indexed question, bytes32 requestId, uint8 status, bytes32 reason);
    event Settled(
        uint256 indexed marketId, uint8 world, uint8 winningSide, bool worldRefunded, uint256 burned, uint256 builderFee
    );
    event Voided(uint256 indexed marketId);
    event BudgetReturned(uint256 indexed marketId, address indexed creator, uint256 amount);
    event Claimed(uint256 indexed marketId, address indexed trader, uint256 amount);
    event PaymentDeferred(address indexed to, uint256 amount);
    event OwedWithdrawn(address indexed to, uint256 amount);
    event OracleConfigProposed(OracleConfig config, uint256 activatableAt);
    event OracleConfigActivated(OracleConfig config);
    event FeeRecipientSet(address feeRecipient);

    error InvalidText();
    error InvalidTimes();
    error InvalidConfig();
    error InvalidChoice();
    error StakeTooSmall();
    error UnknownMarket();
    error MarketNotOpen();
    error BettingClosed();
    error TooEarly();
    error NothingToAsk();
    error NotSettleable();
    error NotVoidable();
    error AlreadyClaimed();
    error NothingToClaim();
    error UnknownAsk();
    error BadAttestation();
    error ZeroAddress();
    error DuplicateAsk();
    error BudgetTooHigh(uint256 budget, uint256 maxBudget);
    error ConfigExpired();

    // ---------------------------------------------------------------------------------------------------------------
    // Construction and configuration
    // ---------------------------------------------------------------------------------------------------------------

    /// @param owner_ Can rotate the oracle configuration for future markets and change the fee recipient.
    /// @param imd_ IMD on this chain (Robinhood Chain: 0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127).
    /// @param intake_ The IdentityMD Intake (0xa43e6f75ee006411f79ac1c84120606c2330de82).
    /// @param oracleSigner_ The oracle's attester (0x5598aa9146215bc13eb26f2c692ad1461fd32982).
    /// @param feeRecipient_ Receives the 1% fee.
    constructor(address owner_, IERC20 imd_, IIntake intake_, address oracleSigner_, address feeRecipient_)
        Ownable(owner_)
        EIP712("IdentityMD Oracle", "2")
    {
        if (address(imd_) == address(0) || feeRecipient_ == address(0)) revert ZeroAddress();
        imd = imd_;
        feeRecipient = feeRecipient_;
        OracleConfig memory config = OracleConfig({
            intake: intake_, signer: oracleSigner_, price: 0.5 ether, panelSize: 5, quorum: 4, action: ORACLE_ACTION
        });
        _validateConfig(config);
        oracleConfig = config;
        emit OracleConfigActivated(config);
        emit FeeRecipientSet(feeRecipient_);
    }

    /// @notice Proposes a new oracle configuration for future markets. Activatable after CONFIG_DELAY.
    function proposeOracleConfig(OracleConfig calldata config) external onlyOwner {
        _validateConfig(config);
        pendingOracleConfig = config;
        pendingOracleConfigAt = block.timestamp + CONFIG_DELAY;
        emit OracleConfigProposed(config, pendingOracleConfigAt);
    }

    /// @notice Activates the proposed configuration, between CONFIG_DELAY and CONFIG_DELAY + CONFIG_WINDOW after
    ///         it was proposed. Markets created earlier keep theirs.
    function activateOracleConfig() external onlyOwner {
        uint256 at = pendingOracleConfigAt;
        if (at == 0 || block.timestamp < at) revert TooEarly();
        if (block.timestamp > at + CONFIG_WINDOW) revert ConfigExpired();
        oracleConfig = pendingOracleConfig;
        delete pendingOracleConfig;
        pendingOracleConfigAt = 0;
        emit OracleConfigActivated(oracleConfig);
    }

    function setFeeRecipient(address feeRecipient_) external onlyOwner {
        if (feeRecipient_ == address(0)) revert ZeroAddress();
        feeRecipient = feeRecipient_;
        emit FeeRecipientSet(feeRecipient_);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Markets
    // ---------------------------------------------------------------------------------------------------------------

    /// @notice Creates a market. The creator deposits two oracle questions' worth of IMD (1 IMD at 0.5 IMD each),
    ///         which pays for its resolution; what is not spent is returned at settlement or void.
    /// @param condition The event the market is conditional on, e.g. "The Clarity Act is signed into US law".
    /// @param outcome What traders predict, e.g. "ETH closes above 5000 USD on Coinbase on 2026-12-01".
    /// @param rules How the oracle should judge both, including the sources to use.
    /// @param closeTime Staking stops at this unix time. Set it before the condition or outcome can be known:
    ///        stakes are accepted until then whatever has become public.
    /// @param resolveTime Both statements are judged as of this unix time; resolution can be requested from then.
    /// @param maxBudget The most IMD the creator agrees to deposit (two oracle questions at the active price).
    ///        The call reverts if an oracle configuration activated meanwhile charges more.
    function createMarket(
        string calldata condition,
        string calldata outcome,
        string calldata rules,
        uint64 closeTime,
        uint64 resolveTime,
        uint256 maxBudget
    ) external nonReentrant returns (uint256 marketId) {
        _validateText(condition, MAX_CONDITION_LENGTH);
        _validateText(outcome, MAX_OUTCOME_LENGTH);
        _validateText(rules, MAX_RULES_LENGTH);
        // The oracle lowercases a definition that is exactly an address or a 32-byte hex string before hashing it.
        // Such a value has no space, so requiring one keeps the hash this contract computes equal to the oracle's.
        if (!_hasSpace(rules)) revert InvalidText();
        if (closeTime <= block.timestamp || resolveTime < closeTime || resolveTime > block.timestamp + MAX_HORIZON) {
            revert InvalidTimes();
        }

        marketId = ++marketCount;
        Market storage m = _markets[marketId];
        m.creator = msg.sender;
        m.closeTime = closeTime;
        m.resolveTime = resolveTime;
        m.voidAfter = resolveTime + uint64(RESOLUTION_PERIOD);
        m.oracle = oracleConfig;
        m.budget = uint256(m.oracle.price) * 2;
        if (m.budget > maxBudget) revert BudgetTooHigh(m.budget, maxBudget);
        m.condition = condition;
        m.outcome = outcome;
        m.rules = rules;

        imd.safeTransferFrom(msg.sender, address(this), m.budget);
        emit MarketCreated(marketId, msg.sender, closeTime, resolveTime, condition, outcome, rules);
    }

    /// @notice Stakes IMD on `side` (YES 0, NO 1) of the outcome in `world` (condition happens 0, does not 1).
    function stake(uint256 marketId, uint8 world, uint8 side, uint256 amount) external nonReentrant {
        Market storage m = _market(marketId);
        if (m.status != Status.Open) revert MarketNotOpen();
        if (block.timestamp >= m.closeTime) revert BettingClosed();
        if (world > 1 || side > 1) revert InvalidChoice();
        if (amount < MIN_STAKE) revert StakeTooSmall();

        m.pools[world][side] += amount;
        _stakes[marketId][msg.sender][world][side] += amount;

        imd.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(marketId, msg.sender, world, side, amount);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Resolution
    // ---------------------------------------------------------------------------------------------------------------

    /// @notice Asks the oracle every question the market still needs. Anyone can call it from resolveTime.
    ///         The first ask of each question is paid from the market's budget; a retry, allowed RETRY_DELAY after
    ///         the last ask of that question if it has not been answered, is paid by the caller.
    /// @return asked How many questions were asked.
    function requestResolution(uint256 marketId) external nonReentrant returns (uint256 asked) {
        Market storage m = _market(marketId);
        if (m.status != Status.Open) revert MarketNotOpen();
        if (block.timestamp < m.resolveTime) revert TooEarly();
        if (block.timestamp > m.voidAfter) revert MarketNotOpen();

        for (uint8 q = 0; q < 2; ++q) {
            if (_askable(m, q)) {
                _ask(marketId, m, q);
                ++asked;
            }
        }
        if (asked == 0) revert NothingToAsk();
    }

    /// @notice The Intake's callback with a signed oracle answer. Selector 0x510379c7.
    function onOracleResult(bytes32 requestId, Attestation calldata a, bytes calldata signature) external {
        bytes32 key = _askKey(msg.sender, requestId);
        Ask memory ask = asks[key];
        if (!ask.live) revert UnknownAsk();
        Market storage m = _markets[ask.marketId];

        delete asks[key];
        --m.openAsks[ask.question];

        if (m.status != Status.Open || m.answers[ask.question] != UNANSWERED) {
            emit AnswerIgnored(ask.marketId, ask.question, requestId);
            return;
        }

        OracleConfig memory config = m.oracle;
        if (
            a.questionHash != ask.questionHash || a.answerType != 0 || a.answer.length != 32
                || a.panelSize < config.panelSize || a.quorum < config.quorum || a.agreed < a.quorum
                || a.agreed > a.panelSize || block.timestamp > a.expiresAt
                || a.issuedAt > block.timestamp + ISSUED_AT_TOLERANCE
        ) revert BadAttestation();

        if (!SignatureChecker.isValidSignatureNow(config.signer, attestationDigest(a), signature)) {
            revert BadAttestation();
        }

        uint256 value = abi.decode(a.answer, (uint256));
        if (value > 1) revert BadAttestation();

        m.answers[ask.question] = value == 1 ? ANSWER_TRUE : ANSWER_FALSE;
        emit Answered(ask.marketId, ask.question, value == 1, a.requestId);
    }

    /// @notice The Intake's callback for a refusal (status 1) or no result (2). Selector 0x5a0df71e.
    ///         Unsigned, so it only clears the ask: the question can be asked again at once, paid by the caller.
    function onFailure(bytes32 requestId, uint8 status, bytes32 reason, uint16, uint16, bytes calldata) external {
        bytes32 key = _askKey(msg.sender, requestId);
        Ask memory ask = asks[key];
        if (!ask.live) revert UnknownAsk();
        delete asks[key];
        --_markets[ask.marketId].openAsks[ask.question];
        emit AskFailed(ask.marketId, ask.question, requestId, status, reason);
    }

    /// @notice Settles a market once the oracle has answered both questions.
    function settle(uint256 marketId) external nonReentrant {
        Market storage m = _market(marketId);
        if (!_settleable(m)) revert NotSettleable();
        _settle(marketId, m);
    }

    /// @notice Voids a market that has no usable answer by voidAfter. Every stake is refunded. Refused while an
    ///         unanswered question has an ask younger than RETRY_DELAY still live, so an answer on its way counts.
    function voidMarket(uint256 marketId) external nonReentrant {
        Market storage m = _market(marketId);
        if (!_voidable(m)) revert NotVoidable();
        m.status = Status.Voided;
        emit Voided(marketId);
        _returnBudget(marketId, m);
    }

    /// @notice Pays the caller everything owed to them by a settled or voided market. Settles first if it can.
    function claim(uint256 marketId) external nonReentrant returns (uint256 amount) {
        Market storage m = _market(marketId);
        if (m.status == Status.Open) {
            if (!_settleable(m)) revert NotSettleable();
            _settle(marketId, m);
        }
        if (claimed[marketId][msg.sender]) revert AlreadyClaimed();
        amount = _payout(marketId, m, msg.sender);
        if (amount == 0) revert NothingToClaim();
        claimed[marketId][msg.sender] = true;
        imd.safeTransfer(msg.sender, amount);
        emit Claimed(marketId, msg.sender, amount);
    }

    /// @notice Pays the caller what a settlement or void could not push to them (see `owed`).
    function withdrawOwed() external nonReentrant returns (uint256 amount) {
        amount = owed[msg.sender];
        if (amount == 0) revert NothingToClaim();
        owed[msg.sender] = 0;
        imd.safeTransfer(msg.sender, amount);
        emit OwedWithdrawn(msg.sender, amount);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------------------------------------------------

    function getMarket(uint256 marketId) external view returns (Market memory) {
        if (marketId == 0 || marketId > marketCount) revert UnknownMarket();
        return _markets[marketId];
    }

    /// @notice A trader's stakes, [world][side].
    function stakesOf(uint256 marketId, address trader) external view returns (uint256[2][2] memory) {
        return _stakes[marketId][trader];
    }

    /// @notice What `trader` could claim now (zero before settlement or void, or after claiming).
    function claimable(uint256 marketId, address trader) external view returns (uint256) {
        Market storage m = _markets[marketId];
        if (m.status == Status.Open || claimed[marketId][trader]) return 0;
        return _payout(marketId, m, trader);
    }

    /// @notice Whether `requestResolution` would ask `question` now.
    function askable(uint256 marketId, uint8 question) external view returns (bool) {
        Market storage m = _markets[marketId];
        if (marketId == 0 || marketId > marketCount || question > 1) return false;
        if (m.status != Status.Open || block.timestamp < m.resolveTime || block.timestamp > m.voidAfter) return false;
        return _askable(m, question);
    }

    function settleable(uint256 marketId) external view returns (bool) {
        if (marketId == 0 || marketId > marketCount) return false;
        return _settleable(_markets[marketId]);
    }

    /// @notice Whether `voidMarket` would succeed now.
    function voidable(uint256 marketId) external view returns (bool) {
        if (marketId == 0 || marketId > marketCount) return false;
        return _voidable(_markets[marketId]);
    }

    /// @notice The EIP-712 digest this contract verifies an attestation's signature against.
    function attestationDigest(Attestation calldata a) public view returns (bytes32) {
        return _hashTypedDataV4(_hashAttestation(a));
    }

    /// @notice The canonical question document the oracle hashes, for `question` asked at `windowBlock`.
    function questionDocument(uint256 marketId, uint8 question, uint256 windowBlock)
        public
        view
        returns (string memory)
    {
        Market storage m = _market(marketId);
        if (question > 1) revert InvalidChoice();
        return _questionDocument(marketId, m, question, windowBlock);
    }

    /// @notice The Intake body for `question` asked at `windowBlock`: the question document plus the panel terms.
    function requestBody(uint256 marketId, uint8 question, uint256 windowBlock) public view returns (string memory) {
        Market storage m = _market(marketId);
        if (question > 1) revert InvalidChoice();
        return _requestBody(marketId, m, question, windowBlock);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------------------------------------------------

    function _market(uint256 marketId) internal view returns (Market storage) {
        if (marketId == 0 || marketId > marketCount) revert UnknownMarket();
        return _markets[marketId];
    }

    function _askable(Market storage m, uint8 q) internal view returns (bool) {
        if (m.answers[q] != UNANSWERED) return false;
        return m.openAsks[q] == 0 || block.timestamp >= uint256(m.lastAskAt[q]) + RETRY_DELAY;
    }

    /// @dev Both questions are needed: the outcome decides the winning side in whichever world happened.
    function _settleable(Market storage m) internal view returns (bool) {
        if (m.status != Status.Open) return false;
        return m.answers[CONDITION] != UNANSWERED && m.answers[OUTCOME] != UNANSWERED;
    }

    function _voidable(Market storage m) internal view returns (bool) {
        if (m.status != Status.Open || block.timestamp <= m.voidAfter || _settleable(m)) return false;
        for (uint8 q = 0; q < 2; ++q) {
            if (
                m.answers[q] == UNANSWERED && m.openAsks[q] != 0
                    && block.timestamp < uint256(m.lastAskAt[q]) + RETRY_DELAY
            ) return false;
        }
        return true;
    }

    /// @dev What an ask pays: the Intake's live price when it is below the market's snapshot (the Intake pulls
    ///      exactly `amount`, so paying the snapshot would overpay), else the snapshot. A price above the snapshot
    ///      is refused by the Intake and the market voids at voidAfter, as documented; the caller never pays more
    ///      than the price the market was created with. An Intake without `priceOf` is charged the snapshot.
    function _askPrice(OracleConfig memory config) internal view returns (uint256 price) {
        price = config.price;
        try IIntakePrice(address(config.intake)).priceOf(config.action, address(imd)) returns (uint256 live) {
            if (live != 0 && live < price) price = live;
        } catch {}
    }

    function _ask(uint256 marketId, Market storage m, uint8 q) internal {
        OracleConfig memory config = m.oracle;
        uint256 price = _askPrice(config);
        uint256 windowBlock = block.number - WINDOW_DEPTH;

        if (m.budget >= price) {
            m.budget -= price;
        } else {
            imd.safeTransferFrom(msg.sender, address(this), price);
        }
        totalOracleSpend += price;

        bytes32 questionHash = keccak256(bytes(_questionDocument(marketId, m, q, windowBlock)));
        bytes memory body = bytes(_requestBody(marketId, m, q, windowBlock));

        imd.forceApprove(address(config.intake), price);
        bytes32 requestId = config.intake
            .requestWithFailure(
                config.action,
                body,
                IIntake.Callback({target: address(this), selector: this.onOracleResult.selector}),
                this.onFailure.selector,
                address(imd),
                price
            );
        imd.forceApprove(address(config.intake), 0);

        bytes32 key = _askKey(address(config.intake), requestId);
        if (asks[key].live) revert DuplicateAsk();
        asks[key] = Ask({marketId: marketId, question: q, live: true, questionHash: questionHash});
        ++m.openAsks[q];
        m.lastAskAt[q] = uint64(block.timestamp);

        emit ResolutionRequested(marketId, q, requestId, questionHash, windowBlock);
    }

    function _settle(uint256 marketId, Market storage m) internal {
        uint8 world = m.answers[CONDITION] == ANSWER_TRUE ? WORLD_HAPPENS : WORLD_DOES_NOT;
        uint8 side = m.answers[OUTCOME] == ANSWER_TRUE ? YES : NO;

        uint256 yes = m.pools[world][YES];
        uint256 no = m.pools[world][NO];
        m.status = Status.Settled;
        m.world = world;
        m.winningSide = side;

        uint256 burned;
        uint256 builderFee;
        if (yes == 0 || no == 0) {
            m.worldRefunded = true;
        } else {
            uint256 pot = yes + no;
            uint256 losing = side == YES ? no : yes;
            burned = pot * BURN_BPS / BPS;
            builderFee = pot * BUILDER_BPS / BPS;
            if (burned + builderFee > losing) {
                // The fee never exceeds what the losing side risked, so a winner never nets less than they staked:
                // a world whose only counterparty is dust is as good as refunded, with the dust split 2:1.
                burned = losing * BURN_BPS / FEE_BPS;
                builderFee = losing - burned;
            }
            m.netPot = pot - burned - builderFee;
            totalBurned += burned;
            totalBuilderFees += builderFee;
        }

        emit Settled(marketId, world, side, m.worldRefunded, burned, builderFee);

        _push(BURN_ADDRESS, burned);
        _push(feeRecipient, builderFee);
        _returnBudget(marketId, m);
    }

    function _returnBudget(uint256 marketId, Market storage m) internal {
        uint256 amount = m.budget;
        if (amount == 0) return;
        m.budget = 0;
        _push(m.creator, amount);
        emit BudgetReturned(marketId, m.creator, amount);
    }

    /// @dev Pays a third party (the burn address, the fee recipient, a creator) inside a staker's transaction. IMD
    ///      can refuse a transfer to a blocked address; such a refusal must not block the stakers, so the amount is
    ///      credited to `owed` instead and the recipient collects it with `withdrawOwed`.
    function _push(address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok, bytes memory data) = address(imd).call(abi.encodeCall(IERC20.transfer, (to, amount)));
        if (ok && (data.length == 0 ? address(imd).code.length > 0 : abi.decode(data, (bool)))) return;
        owed[to] += amount;
        emit PaymentDeferred(to, amount);
    }

    function _payout(uint256 marketId, Market storage m, address trader) internal view returns (uint256 amount) {
        uint256[2][2] storage s = _stakes[marketId][trader];
        if (m.status == Status.Voided) return s[0][0] + s[0][1] + s[1][0] + s[1][1];

        uint8 w = m.world;
        uint8 other = 1 - w;
        amount = s[other][YES] + s[other][NO];
        if (m.worldRefunded) {
            amount += s[w][YES] + s[w][NO];
        } else {
            uint256 mine = s[w][m.winningSide];
            if (mine != 0) amount += mine * m.netPot / m.pools[w][m.winningSide];
        }
    }

    function _askKey(address intake, bytes32 requestId) internal pure returns (bytes32) {
        return keccak256(abi.encode(intake, requestId));
    }

    function _hashAttestation(Attestation calldata a) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                abi.encode(
                    ATTESTATION_TYPEHASH,
                    a.requestId,
                    a.chainId,
                    a.questionHash,
                    a.answerType,
                    keccak256(a.answer),
                    a.figure,
                    a.fromBlock
                ),
                abi.encode(
                    a.toBlock, a.blockHash, a.panelJobId, a.panelSize, a.quorum, a.agreed, a.issuedAt, a.expiresAt
                )
            )
        );
    }

    /// @dev The question text. It names this contract and the market so it is unique to them.
    function _questionText(uint256 marketId, Market storage m, uint8 q) internal view returns (string memory) {
        return string.concat(
            "Conditionals market ",
            marketId.toString(),
            " on Robinhood Chain contract ",
            address(this).toHexString(),
            ", ",
            q == CONDITION ? "condition" : "outcome",
            " statement. Was the following statement true as of unix time ",
            uint256(m.resolveTime).toString(),
            " (UTC)? Statement: ",
            q == CONDITION ? m.condition : m.outcome
        );
    }

    /// @dev Definitions sorted by key: "asOf", then "rules".
    function _definitions(Market storage m) internal view returns (string memory) {
        return string.concat(
            "{\"asOf\":\"Judge the statement by what had happened by unix time ",
            uint256(m.resolveTime).toString(),
            " (UTC). Blockchain blocks are context only.\",\"rules\":\"",
            m.rules,
            "\"}"
        );
    }

    /// @dev Canonical question document: compact JSON with sorted keys, as the oracle hashes it
    ///      (https://imd.fun/docs/#intake-binding-an-answer-to-its-request). Text is restricted to printable ASCII
    ///      without quotes or backslashes, so it needs no escaping.
    function _questionDocument(uint256 marketId, Market storage m, uint8 q, uint256 windowBlock)
        internal
        view
        returns (string memory)
    {
        return string.concat(
            "{\"answerType\":\"bool\",\"chainId\":",
            QUESTION_CHAIN_ID.toString(),
            ",\"definitions\":",
            _definitions(m),
            ",\"evidence\":\"panel\",\"question\":\"",
            _questionText(marketId, m, q),
            "\",\"v\":1,\"window\":",
            _window(windowBlock),
            "}"
        );
    }

    function _requestBody(uint256 marketId, Market storage m, uint8 q, uint256 windowBlock)
        internal
        view
        returns (string memory)
    {
        return string.concat(
            "{\"answerType\":\"bool\",\"chainId\":",
            QUESTION_CHAIN_ID.toString(),
            ",\"definitions\":",
            _definitions(m),
            ",\"evidence\":\"panel\",\"panelSize\":",
            uint256(m.oracle.panelSize).toString(),
            ",\"question\":\"",
            _questionText(marketId, m, q),
            "\",\"quorum\":",
            uint256(m.oracle.quorum).toString(),
            ",\"v\":1,\"validForSeconds\":",
            VALID_FOR_SECONDS.toString(),
            ",\"window\":",
            _window(windowBlock),
            "}"
        );
    }

    function _window(uint256 windowBlock) internal pure returns (string memory) {
        string memory b = windowBlock.toString();
        return string.concat("{\"fromBlock\":", b, ",\"toBlock\":", b, "}");
    }

    /// @dev 1 to maxLength bytes of printable ASCII (0x20-0x7e) without `"` or `\`.
    function _validateText(string calldata text, uint256 maxLength) internal pure {
        bytes calldata b = bytes(text);
        if (b.length == 0 || b.length > maxLength) revert InvalidText();
        for (uint256 i; i < b.length; ++i) {
            bytes1 c = b[i];
            if (c < 0x20 || c > 0x7e || c == 0x22 || c == 0x5c) revert InvalidText();
        }
    }

    function _hasSpace(string calldata text) internal pure returns (bool) {
        bytes calldata b = bytes(text);
        for (uint256 i; i < b.length; ++i) {
            if (b[i] == 0x20) return true;
        }
        return false;
    }

    function _validateConfig(OracleConfig memory config) internal pure {
        if (address(config.intake) == address(0) || config.signer == address(0)) revert ZeroAddress();
        if (
            config.action == bytes32(0) || config.price == 0 || config.price > MAX_PRICE
                || config.panelSize < MIN_PANEL_SIZE || config.panelSize > MAX_PANEL_SIZE || config.quorum < 2
                || config.quorum > config.panelSize
        ) revert InvalidConfig();
    }
}

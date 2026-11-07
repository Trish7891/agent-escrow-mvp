// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AgentEscrow — non-custodial job escrow for agent work
/// @notice Buyer funds a job against a pre-committed terms hash; seller submits an
///         evidence hash; funds release on buyer acceptance, on pre-agreed silence,
///         or on an arbiter ruling. The operator of this contract never holds keys
///         or funds — every movement is triggered by a signature from a party or
///         the arbiter.
///
///         Fee policy: commission is charged ONLY on successful release to the
///         seller. Refunds and unresolved jobs cost nothing. That is the whole
///         "we only earn when the work lands" promise, enforced in code.
///
///         NOT production-ready: needs an independent audit, pull-payment
///         withdrawals instead of push transfers, a per-job arbiter instead of a
///         single immutable one, and KYC/sanctions handling at the boundaries.
contract AgentEscrow {
    enum State {
        None,       // 0 — does not exist
        Funded,     // 1 — buyer's money is locked, awaiting delivery
        Delivered,  // 2 — evidence submitted, buyer review window running
        Released,   // 3 — settled: seller paid
        Refunded,   // 4 — failed: buyer made whole, no fee charged
        Disputed,   // 5 — stake posted, waiting on arbiter
        Unresolved  // 6 — arbiter silent past timeout: refunded, recorded as undecided
    }

    struct Job {
        address buyer;
        address seller;
        uint256 amount;
        uint16  feeBps;           // commission on success, basis points
        uint64  deadline;         // last moment delivery is accepted
        uint64  reviewWindow;     // seconds the buyer has to accept or dispute
        bool    silenceReleases;  // pre-agreed default when the buyer goes quiet
        bytes32 termsHash;        // keccak256 of the agreed job spec
        bytes32 evidenceHash;     // keccak256 of the delivered evidence bundle
        address disputer;
        uint256 stake;
        uint64  deliveredAt;
        uint64  disputedAt;
        State   state;
    }

    uint16 public constant MAX_FEE_BPS = 1_000;        // 10% hard ceiling
    uint64 public constant MIN_REVIEW_WINDOW = 1 hours;
    uint64 public constant ARBITRATION_TIMEOUT = 30 days;

    address public immutable arbiter;
    address public immutable feeRecipient;
    uint256 public immutable disputeStake;

    uint256 public nextJobId = 1;
    mapping(uint256 => Job) private _jobs;

    uint256 private _locked = 1;

    event JobCreated(uint256 indexed id, address indexed buyer, address indexed seller, uint256 amount, bytes32 termsHash, uint16 feeBps, bool silenceReleases);
    event Delivered(uint256 indexed id, bytes32 evidenceHash);
    event Released(uint256 indexed id, uint256 toSeller, uint256 fee);
    event Refunded(uint256 indexed id, uint256 toBuyer);
    event Disputed(uint256 indexed id, address indexed disputer, uint256 stake);
    event Ruled(uint256 indexed id, bool sellerWins, uint256 stakeToWinner);
    event Unresolved(uint256 indexed id, uint256 toBuyer);

    error NotBuyer();
    error NotSeller();
    error NotArbiter();
    error NotParty();
    error BadState(State current);
    error BadAmount();
    error BadTerms();
    error BadFee();
    error BadWindow();
    error BadDeadline();
    error WrongStake();
    error TransferFailed();
    error Reentrant();

    modifier nonReentrant() {
        if (_locked != 1) revert Reentrant();
        _locked = 2;
        _;
        _locked = 1;
    }

    constructor(address arbiter_, address feeRecipient_, uint256 disputeStake_) {
        require(arbiter_ != address(0) && feeRecipient_ != address(0), "zero addr");
        arbiter = arbiter_;
        feeRecipient = feeRecipient_;
        disputeStake = disputeStake_;
    }

    // ---------------------------------------------------------------------
    // lifecycle
    // ---------------------------------------------------------------------

    /// @notice Buyer creates and funds a job in one transaction.
    /// @param termsHash keccak256 of the canonical job spec JSON, agreed by both sides
    ///        before money moves. This is what evidence is judged against; it cannot
    ///        be rewritten later, which is the point.
    function createJob(
        address seller,
        uint64 deadline,
        uint64 reviewWindow,
        bool silenceReleases,
        bytes32 termsHash,
        uint16 feeBps
    ) external payable returns (uint256 id) {
        if (msg.value == 0) revert BadAmount();
        if (seller == address(0) || seller == msg.sender || seller == address(this)) revert BadTerms();
        if (termsHash == bytes32(0)) revert BadTerms();
        if (feeBps > MAX_FEE_BPS) revert BadFee();
        if (deadline <= block.timestamp) revert BadDeadline();
        if (reviewWindow < MIN_REVIEW_WINDOW) revert BadWindow();

        id = nextJobId++;
        Job storage j = _jobs[id];
        j.buyer = msg.sender;
        j.seller = seller;
        j.amount = msg.value;
        j.feeBps = feeBps;
        j.deadline = deadline;
        j.reviewWindow = reviewWindow;
        j.silenceReleases = silenceReleases;
        j.termsHash = termsHash;
        j.state = State.Funded;

        emit JobCreated(id, msg.sender, seller, msg.value, termsHash, feeBps, silenceReleases);
    }

    /// @notice Seller submits the evidence bundle hash. Only the hash goes on-chain;
    ///         the bundle itself lives off-chain and is content-addressed.
    function deliver(uint256 id, bytes32 evidenceHash) external {
        Job storage j = _jobs[id];
        if (msg.sender != j.seller) revert NotSeller();
        if (j.state != State.Funded) revert BadState(j.state);
        if (block.timestamp > j.deadline) revert BadDeadline();
        if (evidenceHash == bytes32(0)) revert BadTerms();

        j.evidenceHash = evidenceHash;
        j.deliveredAt = uint64(block.timestamp);
        j.state = State.Delivered;

        emit Delivered(id, evidenceHash);
    }

    /// @notice Buyer accepts delivery: seller is paid, commission taken.
    function accept(uint256 id) external nonReentrant {
        Job storage j = _jobs[id];
        if (msg.sender != j.buyer) revert NotBuyer();
        if (j.state != State.Delivered) revert BadState(j.state);
        _release(id, j);
    }

    /// @notice Either party opens a dispute by posting the stake. Stake goes to the
    ///         winner, which is what makes frivolous disputes expensive.
    function dispute(uint256 id) external payable {
        Job storage j = _jobs[id];
        if (msg.sender != j.buyer && msg.sender != j.seller) revert NotParty();
        if (j.state != State.Funded && j.state != State.Delivered) revert BadState(j.state);
        if (msg.value != disputeStake) revert WrongStake();

        j.disputer = msg.sender;
        j.stake = msg.value;
        j.disputedAt = uint64(block.timestamp);
        j.state = State.Disputed;

        emit Disputed(id, msg.sender, msg.value);
    }

    /// @notice Arbiter's ruling. paySeller=true releases to the seller (fee applies),
    ///         false refunds the buyer in full (no fee).
    function rule(uint256 id, bool paySeller) external nonReentrant {
        if (msg.sender != arbiter) revert NotArbiter();
        Job storage j = _jobs[id];
        if (j.state != State.Disputed) revert BadState(j.state);

        uint256 stake_ = j.stake;
        j.stake = 0;
        j.disputer = address(0);

        if (paySeller) {
            _release(id, j);                      // sets state = Released
            _send(stake_ > 0 ? j.seller : address(0), stake_);
            emit Ruled(id, true, stake_);
        } else {
            uint256 amt = j.amount;
            j.amount = 0;
            j.state = State.Refunded;
            _send(j.buyer, amt + stake_);
            emit Ruled(id, false, stake_);
            emit Refunded(id, amt);
        }
        // stake follows the winner: if the disputer won, they simply keep their own
        // stake back, which the two branches above accomplish.
    }

    /// @notice Pre-agreed default when the buyer goes silent inside the review window.
    ///         The direction was fixed at job creation, in public, before money moved.
    function claimSilence(uint256 id) external nonReentrant {
        Job storage j = _jobs[id];
        if (j.state != State.Delivered) revert BadState(j.state);
        if (block.timestamp < j.deliveredAt + j.reviewWindow) revert BadDeadline();

        if (j.silenceReleases) {
            _release(id, j);
        } else {
            uint256 amt = j.amount;
            j.amount = 0;
            j.state = State.Refunded;
            _send(j.buyer, amt);
            emit Refunded(id, amt);
        }
    }

    /// @notice Nothing delivered by the deadline: buyer recovers, nobody pays a fee.
    function claimExpiry(uint256 id) external nonReentrant {
        Job storage j = _jobs[id];
        if (j.state != State.Funded) revert BadState(j.state);
        if (block.timestamp <= j.deadline) revert BadDeadline();

        uint256 amt = j.amount;
        j.amount = 0;
        j.state = State.Refunded;
        _send(j.buyer, amt);
        emit Refunded(id, amt);
    }

    /// @notice Arbiter produced no ruling within ARBITRATION_TIMEOUT. Funds return to
    ///         the buyer and the job is recorded as Unresolved — the third column of
    ///         the ledger, not silently counted as a failure.
    function claimArbiterSilence(uint256 id) external nonReentrant {
        Job storage j = _jobs[id];
        if (j.state != State.Disputed) revert BadState(j.state);
        if (block.timestamp < j.disputedAt + ARBITRATION_TIMEOUT) revert BadDeadline();

        uint256 amt = j.amount;
        uint256 stake_ = j.stake;
        j.amount = 0;
        j.stake = 0;
        j.state = State.Unresolved;
        _send(j.buyer, amt);
        if (stake_ > 0) _send(j.disputer, stake_);

        emit Unresolved(id, amt);
    }

    // ---------------------------------------------------------------------
    // views
    // ---------------------------------------------------------------------

    function getJob(uint256 id) external view returns (Job memory) {
        return _jobs[id];
    }

    /// @notice Fee that would be charged if this job released right now.
    function quoteFee(uint256 id) public view returns (uint256) {
        Job storage j = _jobs[id];
        return (j.amount * j.feeBps) / 10_000;
    }

    // ---------------------------------------------------------------------
    // internals
    // ---------------------------------------------------------------------

    function _release(uint256 id, Job storage j) private {
        uint256 amt = j.amount;
        uint256 fee = (amt * j.feeBps) / 10_000;
        j.amount = 0;
        j.state = State.Released;

        emit Released(id, amt - fee, fee);

        if (fee > 0) _send(feeRecipient, fee);
        _send(j.seller, amt - fee);
    }

    function _send(address to, uint256 value) private {
        if (to == address(0) || value == 0) return;
        (bool ok, ) = payable(to).call{value: value}("");
        if (!ok) revert TransferFailed();
    }
}

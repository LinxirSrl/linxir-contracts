// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IGaming {
    function registerPlay(
        uint256 gameId,
        address user,
        uint256 amount
    ) external;
}

/**
 * @title LinxirToken
 * @author Linxir Project
 * @notice ERC20 token with advanced vesting, internal wallet controls, transfer restrictions, staking and migration.
 * @dev All vesting, staking and internal transfer rules are enforced at token level for maximum security.
 */
contract LinxirToken is ERC20, Ownable {
    // ------------------------------------------------------------------------
    // 🔐 Constants & Supply
    // ------------------------------------------------------------------------

    /// @notice Total initial supply (2 Billion tokens)
    uint256 public constant INITIAL_SUPPLY = 2_000_000_000 * 1e18;

    // ------------------------------------------------------------------------
    // 📦 Wallet Addresses (Set at deployment)
    // ------------------------------------------------------------------------

    address public presaleWallet;
    address public stakingWallet;
    address public gamingWallet;
    address public immutable liquidityWallet;
    address public immutable teamWallet;
    address public immutable marketingWallet;

    /// @notice Wallet that receives the 1% fee from `transferWithFee`
    address public feeRecipient;

    /// @notice DEX pool address (e.g. Uniswap)
    address public dexPoolAddress;

    /// @notice Internal smart contracts
    address public presaleContract;
    address public stakingContract;
    address public gamingContract;

    /// @dev One-time flags to prevent overwriting wallet addresses
    bool private presaleWalletSet;
    bool private stakingWalletSet;
    bool private gamingWalletSet;

    /// @notice CEX whitelist for liquidityWallet transfer permission
    mapping(address => bool) public isCexPool;

    // ------------------------------------------------------------------------
    // 📆 Presale & Lifecycle Flags
    // ------------------------------------------------------------------------

    /// @notice Unix timestamp when presale ends. Zero = not ended
    uint256 public presaleEndTime;

    /// @notice Current presale phase: 0 (not started) to 5 (final phase)
    uint8 public currentPresalePhase;

    /// @notice Distribution and burn state
    bool public initialDistributed;
    bool public presaleBurned;
    bool public stakingBurned;
    bool public migrationEnabled;

    // ------------------------------------------------------------------------
    // 🧠 Vesting Logic
    // ------------------------------------------------------------------------

    /// @notice Struct defining a vesting allocation from a specific source
    struct VestingAllocation {
        uint256 total;         // Total tokens assigned
        uint256 claimed;       // Tokens already claimed (unused in current version)
        uint256 cliff;         // Cliff time in seconds after `presaleEndTime`
        uint256 duration;      // Duration of vesting after cliff
        bool fixedRelease;     // If true, all tokens release after cliff (no linear vesting)
    }

    /// @notice Enum-like constants used to differentiate vesting sources
    bytes32 public constant SOURCE_PRESALE   = keccak256("presale");
    bytes32 public constant SOURCE_MARKETING = keccak256("marketing");
    bytes32 public constant SOURCE_TEAM      = keccak256("team");
    bytes32 public constant SOURCE_GAMING    = keccak256("gaming");
    bytes32 public constant SOURCE_REWARDS   = keccak256("staking");

    /// @notice Vesting data by user and source
    mapping(address => mapping(bytes32 => VestingAllocation)) public vestings;

    /// @notice Presale vesting tracking per user (amount + phase purchased)
    struct PresaleVesting {
        uint256 amount;
        uint8 phase;
    }
    mapping(address => PresaleVesting[]) public presaleVestings;

    /// @notice Gaming vesting tracking per user (amount + timestamp assigned)
    struct GamingVesting {
        uint256 amount;
        uint256 timestamp;
    }
    mapping(address => GamingVesting[]) public gamingVestings;

    /// @notice Deposits made to gaming contracts by user (for analytics)
    mapping(address => uint256) public gamingDeposits;

    // ------------------------------------------------------------------------
    // 🔁 Migration Data
    // ------------------------------------------------------------------------

    /// @notice Struct tracking token migration data to LinxirChain
    struct MigrationData {
        uint256 usable;                // Unlocked tokens at migration
        uint256 staked;                // Staked tokens at migration
        uint256[5] vestedBySource;     // Remaining locked tokens by vesting source
        bool migrated;                 // True if already migrated
    }
    mapping(address => MigrationData) public migrationRecords;

    /**
     * @notice Returns the current blockchain timestamp with test offset
     * @dev Used for simulating time-dependent vesting logic in tests
     */
    function currentTime() public view returns (uint256) {
        return block.timestamp;
    }

    // ------------------------------------------------------------------------
    // 📣 Events
    // ------------------------------------------------------------------------

    event MarketingTransfer(address indexed to, uint256 amount, string reason);
    event PresaleEnded(uint256 timestamp);
    event PresalePhaseAdvanced(uint8 newPhase);
    event GamingDeposit(address indexed user, address indexed gamingContract, uint256 amount);

    event InternalTransfer(
        address indexed from,
        address indexed to,
        uint256 amount,
        string walletType,
        string reason
    );

    event TokensMigrated(
        address indexed user,
        uint256 usable,
        uint256 staked,
        uint256[5] vestedBySource
    );

    // ------------------------------------------------------------------------
    // 🏗 Constructor
    // ------------------------------------------------------------------------

    /**
     * @notice Initializes the Linxir token and mints the entire supply to the contract itself.
     * @param _presale Wallet receiving presale allocation
     * @param _staking Wallet for staking rewards
     * @param _liquidity Wallet for liquidity provisioning (immutable)
     * @param _team Wallet for team allocation (immutable)
     * @param _marketing Wallet for marketing allocation (immutable)
     * @param _gaming Wallet for gaming incentives
     */
    constructor(
        address _presale,
        address _staking,
        address _liquidity,
        address _team,
        address _marketing,
        address _gaming
    ) ERC20("Linxir", "LXR") Ownable(msg.sender) {
        require(_staking != address(0), "Invalid staking wallet");
        require(_liquidity != address(0), "Invalid liquidity wallet");
        require(_team != address(0), "Invalid team wallet");
        require(_marketing != address(0), "Invalid marketing wallet");
        require(_gaming != address(0), "Invalid gaming wallet");

        presaleWallet = _presale;
        stakingWallet = _staking;
        liquidityWallet = _liquidity;
        teamWallet = _team;
        marketingWallet = _marketing;
        gamingWallet = _gaming;

        feeRecipient = msg.sender;

        // Mint total supply to the contract
        _mint(address(this), INITIAL_SUPPLY);
    }
        // ------------------------------------------------------------------------
    // 🎁 Initial Distribution Logic
    // ------------------------------------------------------------------------

    /**
     * @notice Distributes the initial supply to predefined wallets.
     * @dev Can only be called once. Vesting is applied only to team allocation.
     */
    function initialDistribution() external onlyOwner {
        require(!initialDistributed, "Already distributed");
        require(balanceOf(address(this)) == INITIAL_SUPPLY, "Incorrect balance");

        initialDistributed = true;

        _transfer(address(this), presaleWallet,   (INITIAL_SUPPLY * 40) / 100);
        _transfer(address(this), stakingWallet,   (INITIAL_SUPPLY * 20) / 100);
        _transfer(address(this), liquidityWallet, (INITIAL_SUPPLY * 15) / 100);
        _internalVestTransfer(address(this), teamWallet, (INITIAL_SUPPLY * 5) / 100, SOURCE_TEAM);
        _transfer(address(this), marketingWallet, (INITIAL_SUPPLY * 15) / 100);
        _transfer(address(this), gamingWallet,    (INITIAL_SUPPLY * 5)  / 100);
    }

    // ------------------------------------------------------------------------
    // 🔁 Vesting Transfer Logic
    // ------------------------------------------------------------------------

    /**
     * @notice Internal function to transfer tokens and apply vesting rules.
     * @dev Used by presale, staking, marketing, gaming, team wallets.
     */
    function _vestTransfer(address from, address to, uint256 amount) internal {
        bytes32 source;

        if (from == presaleWallet) source = SOURCE_PRESALE;
        else if (from == marketingWallet) source = SOURCE_MARKETING;
        else if (from == gamingWallet) source = SOURCE_GAMING;
        else if (from == teamWallet) source = SOURCE_TEAM;
        else if (from == stakingWallet) source = SOURCE_REWARDS;
        else revert("Invalid source wallet");

        _transfer(from, to, amount);
        emit InternalTransfer(from, to, amount, _walletTypeLabel(from), "Vest transfer");

        VestingAllocation storage v = vestings[to][source];
        v.total += amount;

        if (source == SOURCE_PRESALE) {
            require(currentPresalePhase >= 1 && currentPresalePhase <= 5, "Invalid presale phase");
            presaleVestings[to].push(PresaleVesting({
                amount: amount,
                phase: currentPresalePhase
            }));
        }

        if (source == SOURCE_MARKETING) {
            v.cliff = 20 days;
            v.fixedRelease = true;
        } else if (source == SOURCE_TEAM) {
            v.cliff = 365 days;
            v.duration = 365 days;
            v.fixedRelease = false;
        } else if (source == SOURCE_GAMING) {
            // Vesting solo durante la presale
            if (presaleEndTime == 0) {
                gamingVestings[to].push(GamingVesting({
                    amount: amount,
                    timestamp: currentTime()
                }));
            } else {
                _transfer(msg.sender, to, amount); // unlocked post-presale
            }
        } else if (source == SOURCE_REWARDS) {
            require(
                presaleEndTime > 0 || migrationEnabled,
                "Presale not ended and migration not enabled"
            );
            v.cliff = 10 days;
            v.fixedRelease = true;
        }
    }

    /**
     * @notice Allows user to trigger a vest transfer from themselves.
     */
    function vestTransfer(address to, uint256 amount) external {
        _vestTransfer(msg.sender, to, amount);
    }

    /**
     * @notice Internal transfer and vest allocation (used for team during initial distribution)
     */
    function _internalVestTransfer(address from, address to, uint256 amount, bytes32 source) internal {
        _transfer(from, to, amount);
        emit InternalTransfer(from, to, amount, _walletTypeLabel(from), "Internal vesting");

        VestingAllocation storage v = vestings[to][source];
        v.total += amount;

        if (source == SOURCE_TEAM) {
            v.cliff = 365 days;
            v.duration = 365 days;
            v.fixedRelease = false;
        }
    }

    /**
     * @notice Calculates initial unlocked tokens from presale based on phase.
     */
    function _initialUnlockedPresale(address user) internal view returns (uint256 total) {
        PresaleVesting[] memory vestingList = presaleVestings[user];

        for (uint256 i = 0; i < vestingList.length; i++) {
            uint256 percent;
            if (vestingList[i].phase == 1) percent = 10;
            else if (vestingList[i].phase == 2) percent = 15;
            else if (vestingList[i].phase == 3) percent = 20;
            else if (vestingList[i].phase == 4) percent = 25;
            else if (vestingList[i].phase == 5) percent = 30;

            total += (vestingList[i].amount * percent) / 100;
        }
    }

    /**
     * @notice Returns the total unlocked balance from a specific vesting source.
     */
    function unlockedBalanceBySource(address user, bytes32 source) public view returns (uint256) {
        if (presaleEndTime == 0) return 0;
        uint256 nowTime = currentTime();

        VestingAllocation memory v = vestings[user][source];
        if (v.total == 0) return 0;

        if (source == SOURCE_PRESALE && !v.fixedRelease) {
            // Multi-phase presale logic
            uint256 unlocked;
            PresaleVesting[] memory list = presaleVestings[user];
            for (uint256 i = 0; i < list.length; i++) {
                uint8 phase = list[i].phase;
                uint256 amount = list[i].amount;

                uint256 cliff = 1 days;
                uint256 duration;
                uint256 immediatePercent;

                if (phase == 1) { duration = 200 days; immediatePercent = 10; }
                else if (phase == 2) { duration = 180 days; immediatePercent = 15; }
                else if (phase == 3) { duration = 150 days; immediatePercent = 20; }
                else if (phase == 4) { duration = 120 days; immediatePercent = 25; }
                else if (phase == 5) { duration = 90 days;  immediatePercent = 30; }
                else { continue; }

                if (nowTime >= presaleEndTime) {
                    unlocked += (amount * immediatePercent) / 100;
                    if (nowTime >= presaleEndTime + cliff) {
                        uint256 timePassed = nowTime - (presaleEndTime + cliff);
                        if (timePassed > duration) timePassed = duration;

                        uint256 vestingPercent = 100 - immediatePercent;
                        unlocked += (amount * vestingPercent * timePassed) / (duration * 100);
                    }
                }
            }
            return unlocked;
        }

        else if (source == SOURCE_GAMING) {
            // 20% subito + 80% lineare in 150 giorni
            GamingVesting[] memory list = gamingVestings[user];
            uint256 unlocked;

            for (uint256 i = 0; i < list.length; i++) {
                uint256 amount = list[i].amount;
                uint256 cliff = 1 days;
                uint256 duration = 150 days;
                uint256 immediatePercent = 20;

                if (nowTime >= presaleEndTime) {
                    unlocked += (amount * immediatePercent) / 100;

                    if (nowTime >= presaleEndTime + cliff) {
                        uint256 timePassed = nowTime - (presaleEndTime + cliff);
                        if (timePassed > duration) timePassed = duration;
                        unlocked += (amount * (100 - immediatePercent) * timePassed) / (duration * 100);
                    }
                }
            }

            return unlocked;
        }

        else if (v.fixedRelease) {
            // Full release after cliff
            if (nowTime >= presaleEndTime + v.cliff) return v.total;
            return 0;
        }

        else {
            // Linear release after cliff
            if (nowTime < presaleEndTime + v.cliff) return 0;
            uint256 timePassed = nowTime - (presaleEndTime + v.cliff);
            if (timePassed > v.duration) timePassed = v.duration;
            return (v.total * timePassed) / v.duration;
        }
    }

    /**
     * @notice Returns locked tokens from a specific source
     */
    function lockedBalanceBySource(address user, bytes32 source) public view returns (uint256) {
        if (presaleEndTime == 0) return vestings[user][source].total;
        uint256 unlocked = unlockedBalanceBySource(user, source);
        uint256 total = vestings[user][source].total;
        return total > unlocked ? total - unlocked : 0;
    }

    /**
     * @notice Returns sum of unlocked tokens across all vesting sources
     */
    function totalUnlockedVesting(address user) public view returns (uint256 total) {
        bytes32[5] memory sources = [
            SOURCE_PRESALE,
            SOURCE_MARKETING,
            SOURCE_TEAM,
            SOURCE_GAMING,
            SOURCE_REWARDS
        ];
        for (uint256 i = 0; i < sources.length; i++) {
            total += unlockedBalanceBySource(user, sources[i]);
        }
    }

    /**
     * @notice Returns sum of locked tokens across all vesting sources
     */
    function totalLockedVesting(address user) public view returns (uint256 total) {
        if (presaleEndTime == 0) {
            bytes32[5] memory sources = [
                SOURCE_PRESALE,
                SOURCE_MARKETING,
                SOURCE_TEAM,
                SOURCE_GAMING,
                SOURCE_REWARDS
            ];
            for (uint256 i = 0; i < sources.length; i++) {
                total += vestings[user][sources[i]].total;
            }
        } else {
            total += lockedBalanceBySource(user, SOURCE_PRESALE);
            total += lockedBalanceBySource(user, SOURCE_MARKETING);
            total += lockedBalanceBySource(user, SOURCE_TEAM);
            total += lockedBalanceBySource(user, SOURCE_GAMING);
            total += lockedBalanceBySource(user, SOURCE_REWARDS);
        }
    }

    /**
     * @notice Returns user usable (unlocked) token balance.
     * @dev Excludes locked vesting and staked tokens.
     */
    function usableBalance(address user) public view returns (uint256) {
        uint256 balance = balanceOf(user);
        uint256 locked = totalLockedVesting(user);
        return balance > locked ? balance - locked : 0;
    }

    /**
     * @notice Returns full balance (ERC20 + staked), used by frontend.
     */
    function userTotalSupply(address account) external view returns (uint256) {
        return super.balanceOf(account);
    }
        // ------------------------------------------------------------------------
    // 💸 Transfer with Fee
    // ------------------------------------------------------------------------

    /**
     * @notice Transfers tokens with a 1% fee to the feeRecipient.
     * @dev Only unlocked balance is allowed. Requires presale to be ended.
     */
    function transferWithFee(address to, uint256 amount) external {
        require(presaleEndTime > 0, "Transfers not allowed before presale end");
        require(to != address(0), "Invalid recipient");

        uint256 fee = amount / 100;
        uint256 total = amount + fee;

        require(usableBalance(msg.sender) >= total, "Insufficient unlocked balance");

        _transfer(msg.sender, feeRecipient, fee);
        _transfer(msg.sender, to, amount);
    }

    // ------------------------------------------------------------------------
    // 🛠 Wallet + Contract Setters (One-time)
    // ------------------------------------------------------------------------

    function setPresaleContract(address _presale) external onlyOwner {
        require(!presaleWalletSet, "Presale wallet already set");
        require(_presale != address(0), "Invalid address");

        presaleContract = _presale;
        presaleWallet = _presale;
        presaleWalletSet = true;
    }

    function setStakingContract(address _staking) external onlyOwner {
        require(!stakingWalletSet, "Staking wallet already set");
        require(_staking != address(0), "Invalid address");

        stakingContract = _staking;
        stakingWallet = _staking;
        stakingWalletSet = true;
    }

    function setGamingContract(address _gaming) external onlyOwner {
        require(!gamingWalletSet, "Gaming wallet already set");
        require(_gaming != address(0), "Invalid address");

        gamingContract = _gaming;
        gamingWallet = _gaming;
        gamingWalletSet = true;
    }

    /**
     * @notice Updates the address receiving fees
     */
    function setFeeRecipient(address _recipient) external onlyOwner {
        require(_recipient != address(0), "Invalid address");
        feeRecipient = _recipient;
    }

    /**
     * @notice Authorizes a CEX liquidity pool to receive from liquidityWallet
     */
    function setCexPool(address _addr, bool authorized) external onlyOwner {
        require(_addr != address(0), "Invalid address");
        isCexPool[_addr] = authorized;
    }

    function setDexPoolAddress(address _addr) external onlyOwner {
        dexPoolAddress = _addr;
    }

    // ------------------------------------------------------------------------
    // 🎯 Presale Phases & Control
    // ------------------------------------------------------------------------

    function nextPresalePhase() external {
        require(msg.sender == owner() || msg.sender == presaleContract, "Not authorized");
        require(currentPresalePhase < 5, "Presale already in final phase");

        currentPresalePhase += 1;
        emit PresalePhaseAdvanced(currentPresalePhase);
    }

    function endPresale() external onlyOwner {
        require(presaleEndTime == 0, "Presale already ended");
        presaleEndTime = currentTime();
        emit PresaleEnded(presaleEndTime);
    }

    function burnRemainingPresale() external onlyOwner {
        require(presaleEndTime != 0, "Presale not ended yet");
        require(!presaleBurned, "Already burned");

        uint256 balance = balanceOf(presaleWallet);
        _burn(presaleWallet, balance);
        presaleBurned = true;
    }

    function burnRemainingStaking() external onlyOwner {
        require(presaleEndTime != 0, "Presale not ended yet");
        require(!stakingBurned, "Staking already burned");

        uint256 balance = balanceOf(stakingWallet);
        require(balance > 0, "No staking tokens to burn");

        _burn(stakingWallet, balance);
        stakingBurned = true;
    }

    // ------------------------------------------------------------------------
    // 🎮 Gaming Integration
    // ------------------------------------------------------------------------

    function burnFromGaming(uint256 amount) external {
        require(msg.sender == gamingContract, "Not authorized");
        _burn(msg.sender, amount);
    }

    function withdrawGamingTokens(address to, uint256 amount) external {
        require(msg.sender == gamingContract || msg.sender == owner(), "Only gaming contract");
        _transfer(gamingWallet, to, amount);
    }

    function depositToGaming(uint256 gameId, uint256 amount) external {
        require(gamingContract != address(0), "Gaming contract not set");
        require(gameId != 0, "Invalid gameId");
        require(amount > 0, "Amount must be greater than 0");

        require(
            availableBalance(msg.sender) >= amount,
            "Insufficient available balance"
        );

        if (presaleEndTime == 0) {
            // During presale: consume from vestings
            bytes32[5] memory sources = [
                SOURCE_PRESALE,
                SOURCE_MARKETING,
                SOURCE_GAMING,
                SOURCE_TEAM,
                SOURCE_REWARDS
            ];

            uint256 remaining = amount;
            for (uint256 i = 0; i < sources.length && remaining > 0; i++) {
                VestingAllocation storage v = vestings[msg.sender][sources[i]];
                if (v.total == 0) continue;

                uint256 toUse = v.total >= remaining ? remaining : v.total;
                v.total -= toUse;
                remaining -= toUse;
            }

            require(remaining == 0, "Not enough vested tokens");
        }

        _transfer(msg.sender, gamingContract, amount);

        IGaming(gamingContract).registerPlay(gameId, msg.sender, amount);
        gamingDeposits[msg.sender] += amount;

        emit GamingDeposit(msg.sender, gamingContract, amount);
    }

    // ------------------------------------------------------------------------
    // 📤 Controlled Vest Transfer (external)
    // ------------------------------------------------------------------------

    function vestTransferFromWallet(address from, address to, uint256 amount) external {
        bool isFromStaking = from == stakingWallet;
        bool isFromGaming = from == gamingWallet;

        bool authorized =
            msg.sender == presaleContract ||
            msg.sender == owner() ||
            (isFromStaking && msg.sender == stakingContract) ||
            (isFromGaming && msg.sender == gamingContract);

        require(authorized, "Not authorized");
        require(balanceOf(from) >= amount, "Insufficient balance");

        if (isFromStaking) {
            _vestTransfer(from, to, amount);
            emit InternalTransfer(from, to, amount, "Staking", "Staking reward (vested)");
            return;
        }

        _vestTransfer(from, to, amount);

        string memory label = isFromGaming ? "Gaming" : "Presale";
        emit InternalTransfer(from, to, amount, label, "vestTransferFromWallet");

        if (msg.sender == owner() && from == presaleWallet) {
            (bool success, ) = presaleContract.call(
                abi.encodeWithSignature("registerTokenSale(address,uint256)", to, amount)
            );
            require(success, "registerTokenSale failed");
        }
    }

    // ------------------------------------------------------------------------
    // 🌐 Migration to LinxirChain
    // ------------------------------------------------------------------------

    function enableMigration() external onlyOwner {
        require(!migrationEnabled, "Already enabled");
        migrationEnabled = true;
    }

    function migrateTokens() external {
        require(migrationEnabled, "Migration not enabled");
        require(currentPresalePhase >= 4, "Migration not available yet");
        require(!migrationRecords[msg.sender].migrated, "Already migrated");

        uint256 totalBalance = super.balanceOf(msg.sender);
        require(totalBalance > 0, "No tokens to migrate");

        uint256 usable = usableBalance(msg.sender);
        uint256 staked = stakedBalances(msg.sender);

        if (stakingContract != address(0)) {
            (bool ok, bytes memory data) = stakingContract.staticcall(
                abi.encodeWithSignature("getPendingRewards(address)", msg.sender)
            );
            require(ok, "Failed to read pendingRewards");
            uint256 rewards = abi.decode(data, (uint256));
            require(rewards == 0, "Cannot migrate: pending staking rewards");
        }

        uint256[5] memory vested;
        vested[0] = lockedBalanceBySource(msg.sender, SOURCE_PRESALE);
        vested[1] = lockedBalanceBySource(msg.sender, SOURCE_MARKETING);
        vested[2] = lockedBalanceBySource(msg.sender, SOURCE_TEAM);
        vested[3] = lockedBalanceBySource(msg.sender, SOURCE_GAMING);
        vested[4] = lockedBalanceBySource(msg.sender, SOURCE_REWARDS);

        migrationRecords[msg.sender] = MigrationData({
            usable: usable,
            staked: staked,
            vestedBySource: vested,
            migrated: true
        });

        if (staked > 0 && stakingContract != address(0)) {
            (bool ok, ) = stakingContract.call(
                abi.encodeWithSignature("resetStaking(address)", msg.sender)
            );
            require(ok, "Reset staking failed");
        }

        _burn(msg.sender, totalBalance);
        emit TokensMigrated(msg.sender, usable, staked, vested);
    }

    function adminMigrateWallet(address wallet) external onlyOwner {
        require(migrationEnabled, "Migration not enabled");
        require(currentPresalePhase >= 4, "Migration available from phase 4");
        require(_isInternalWallet(wallet), "Not internal wallet");

        uint256 balance = super.balanceOf(wallet);
        require(balance > 0, "No tokens to migrate");

        uint256[5] memory vested;
        vested[0] = lockedBalanceBySource(wallet, SOURCE_PRESALE);
        vested[1] = lockedBalanceBySource(wallet, SOURCE_MARKETING);
        vested[2] = lockedBalanceBySource(wallet, SOURCE_TEAM);
        vested[3] = lockedBalanceBySource(wallet, SOURCE_GAMING);
        vested[4] = lockedBalanceBySource(wallet, SOURCE_REWARDS);

        uint256 usable = usableBalance(wallet);
        uint256 staked = stakedBalances(wallet);

        if (stakingContract != address(0)) {
            (bool ok, bytes memory data) = stakingContract.staticcall(
                abi.encodeWithSignature("getPendingRewards(address)", wallet)
            );
            require(ok, "Failed to read pendingRewards");

            uint256 rewards = abi.decode(data, (uint256));
            require(rewards == 0, "Cannot migrate: pending staking rewards");
        }

        migrationRecords[wallet] = MigrationData({
            usable: usable,
            staked: staked,
            vestedBySource: vested,
            migrated: true
        });

        if (staked > 0 && stakingContract != address(0)) {
            (bool ok, ) = stakingContract.call(
                abi.encodeWithSignature("resetStaking(address)", wallet)
            );
            require(ok, "Reset staking failed");
        }

        _burn(wallet, balance);
        emit TokensMigrated(wallet, usable, staked, vested);
    }

    function getMigrationData(address user) external view returns (
        uint256 usable,
        uint256 staked,
        uint256[5] memory vested
    ) {
        MigrationData memory data = migrationRecords[user];
        return (data.usable, data.staked, data.vestedBySource);
    }

    // ------------------------------------------------------------------------
    // 🔐 Override balanceOf & _update
    // ------------------------------------------------------------------------

    function stakedBalances(address user) public view returns (uint256) {
        if (stakingContract == address(0)) return 0;

        (bool success, bytes memory data) = stakingContract.staticcall(
            abi.encodeWithSignature("getStakedAmount(address)", user)
        );

        if (!success || data.length < 32) return 0;
        return abi.decode(data, (uint256));
    }

    function balanceOf(address account) public view override returns (uint256) {
        return super.balanceOf(account) - stakedBalances(account);
    }

    function availableBalance(address user) public view returns (uint256) {
        return super.balanceOf(user) - stakedBalances(user);
    }

    function _update(address from, address to, uint256 value) internal override {
        // ✅ Allow mint/burn operations (constructor mint, burns)
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        bool fromIsInternal = _isInternalWallet(from);

        bool internalTransferBlocked =
            fromIsInternal &&
            (
                from != liquidityWallet ||
                !(to == dexPoolAddress || isCexPool[to])
            ) &&
            presaleEndTime == 0;

        bool isWhitelistedFunction = (
            msg.sig == this.vestTransfer.selector ||
            msg.sig == this.vestTransferFromWallet.selector ||
            msg.sig == this.burnFromGaming.selector ||
            msg.sig == this.withdrawGamingTokens.selector ||
            msg.sig == this.migrateTokens.selector ||
            msg.sig == this.adminMigrateWallet.selector ||
            msg.sig == this.depositToGaming.selector
        );

        if (internalTransferBlocked && !isWhitelistedFunction) {
            revert("Internal wallets cannot transfer before presale end");
        }

        if (from == teamWallet && msg.sig != this.migrateTokens.selector) {
            require(usableBalance(from) >= value, "Team: insufficient unlocked balance");
        } else if (fromIsInternal && presaleEndTime == 0 && !isWhitelistedFunction) {
            revert("Internal wallets cannot transfer before presale end");
        } else if (!fromIsInternal && msg.sig != this.migrateTokens.selector) {
            if (
                presaleEndTime == 0 &&
                to == gamingContract
            ) {
                // allowed: vestings already consumed in depositToGaming
            } else {
                require(
                    usableBalance(from) >= value,
                    "Trying to transfer locked tokens"
                );
            }
        }

        if (from == marketingWallet) {
            emit MarketingTransfer(to, value, "Marketing wallet transfer");
        }

        if (fromIsInternal && from != address(this) && msg.sig != this.vestTransfer.selector) {
            emit InternalTransfer(from, to, value, _walletTypeLabel(from), "Standard transfer");
        }

        super._update(from, to, value);
    }

    // ------------------------------------------------------------------------
    // 📌 Helpers
    // ------------------------------------------------------------------------

    function _isInternalWallet(address addr) internal view returns (bool) {
        return (
            addr == presaleWallet ||
            addr == stakingWallet ||
            addr == liquidityWallet ||
            addr == teamWallet ||
            addr == marketingWallet ||
            addr == gamingWallet
        );
    }

    function _walletTypeLabel(address wallet) internal view returns (string memory) {
        if (wallet == presaleWallet) return "Presale";
        if (wallet == stakingWallet) return "Staking";
        if (wallet == liquidityWallet) return "Liquidity";
        if (wallet == marketingWallet) return "Marketing";
        if (wallet == gamingWallet) return "Gaming";
        if (wallet == teamWallet) return "Team";
        return "Unknown";
    }
}




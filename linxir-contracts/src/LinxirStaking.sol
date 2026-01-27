// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./LinxirToken.sol";

/**
 * @title LinxirStaking
 * @notice This contract allows users to stake LXR tokens and earn rewards over time.
 *         APR is dynamic based on the staking period, and rewards are distributed
 *         via vesting from the staking wallet defined in LinxirToken.
 *         Includes support for stopping rewards permanently (used for migration) and enabling global reward boosters.
 */
contract LinxirStaking {
    // -----------------------------------------------------
    // State variables
    // -----------------------------------------------------

    LinxirToken public immutable token;
    address public immutable owner;

    bool public stakingEnabled;
    bool public rewardsStopped;
    bool public claimDuringMigrationEnabled;

    uint256 public stakingStartTime;
    uint256 public totalStaked;

    uint256 public rewardsStopTime;

    struct StakeInfo {
        uint256 amount;
        uint256 lastUpdate;
        uint256 rewardDebt;
    }

    BoosterPeriod[] public boosterHistory;

    struct BoosterPeriod {
        uint256 start;
        uint256 end;
        uint256 multiplier;
    }

    address[] public stakers;

    mapping(address => StakeInfo) public stakes;
    mapping(address => bool) public isStaker;

    // -----------------------------------------------------
    // Events
    // -----------------------------------------------------

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event StakingEnabled();
    event StakingDisabled();
    event RewardsStopped(uint256 time);
    event GlobalBoosterActivated(uint256 multiplier, uint256 endTime);
    event GlobalBoosterDisabled();

    // -----------------------------------------------------
    // Constructor & Modifiers
    // -----------------------------------------------------

    /**
     * @dev Sets the token contract and assigns ownership.
     */
    constructor(address _token) {
        require(_token != address(0), "Invalid token address");
        token = LinxirToken(_token);
        owner = msg.sender;
    }

    /**
     * @dev Restricts function to contract owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    // -----------------------------------------------------
    // Admin functions
    // -----------------------------------------------------

    /**
     * @notice Enables staking and sets the staking start time.
     */
    function enableStaking() external onlyOwner {
        require(!stakingEnabled, "Already enabled");
        stakingEnabled = true;

        if (stakingStartTime == 0) {
            stakingStartTime = token.currentTime();
        }

        emit StakingEnabled();
    }

    /**
     * @notice Disables staking without affecting existing stakes.
     */
    function disableStaking() external onlyOwner {
        require(stakingEnabled, "Already disabled");
        stakingEnabled = false;
        emit StakingDisabled();
    }

    /**
     * @notice Enables early claiming of staking rewards during the migration phase.
     * @dev This function is intended to be called only when token migration to the
     *      Linxir native chain is active and before the end of the presale.
     *
     *      When enabled:
     *      - Users are allowed to claim their accumulated staking rewards
     *        even if the presale has not ended yet.
     *      - Claimed rewards are still subject to vesting rules defined in the
     *        LinxirToken contract (e.g. delayed unlock after presale end).
     *
     *      This mechanism ensures that all rewards can be correctly migrated
     *      and re-minted on the new chain with consistent vesting conditions.
     *
     *      ⚠️ This function is NOT meant for regular reward claiming and should
     *      only be used as part of a controlled migration process.
     */
    function enableClaimDuringMigration() external onlyOwner {
        claimDuringMigrationEnabled = true;
    }

    /**
    * @notice Permanently stops reward accumulation (used for migration only)
    * @dev After calling this, rewards will stop accumulating forever.
    *      Users can still claim pending rewards.
    */
    function stopRewards() external onlyOwner {
        require(!rewardsStopped, "Already stopped");
        rewardsStopped = true;
        rewardsStopTime = token.currentTime();
        emit RewardsStopped(rewardsStopTime);
    }

    /**
     * @notice Enables a global reward multiplier (e.g. x2 rewards).
     */
    function setGlobalBooster(uint256 multiplier, uint256 duration) external onlyOwner {
        require(multiplier >= 1 && multiplier <= 10, "Invalid multiplier");
        require(duration > 0, "Duration must be > 0");

        uint256 start = token.currentTime();
        uint256 end = start + duration;

        boosterHistory.push(BoosterPeriod({
            start: start,
            end: end,
            multiplier: multiplier
        }));

        emit GlobalBoosterActivated(multiplier, end);
    }   

    /**
    * @notice Logs the end of current booster period. It does not delete history.
    *         Boosters expire based on time and are immutable once created.
    */
    function disableGlobalBooster() external onlyOwner {
        emit GlobalBoosterDisabled();
    }

    // -----------------------------------------------------
    // User functions
    // -----------------------------------------------------

    /**
     * @notice Stake LXR tokens.
     * @param amount Amount of tokens to stake
     */
    function stake(uint256 amount) external {
        require(stakingEnabled, "Staking disabled");
        require(amount > 0, "Cannot stake zero");
        require(token.balanceOf(msg.sender) >= amount, "Insufficient balance");

        if (!isStaker[msg.sender]) {
            isStaker[msg.sender] = true;
            stakers.push(msg.sender);
        }

        StakeInfo storage user = stakes[msg.sender];
        _updateRewards(msg.sender);

        require(totalStaked + amount <= 250_000_000 * 1e18, "Max staking cap reached");

        user.amount += amount;
        totalStaked += amount;
        user.lastUpdate = token.currentTime();

        if (totalStaked == 250_000_000 * 1e18) {
            stakingEnabled = false;
            emit StakingDisabled();
        }

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Unstake tokens after presale ends.
     */
    function unstake() external {
        require(token.presaleEndTime() > 0, "Presale not ended");

        StakeInfo storage user = stakes[msg.sender];
        require(user.amount > 0, "Nothing to unstake");

        _updateRewards(msg.sender);

        uint256 unstakeAmount = user.amount;
        user.amount = 0;
        totalStaked -= unstakeAmount;
        user.lastUpdate = token.currentTime();

        emit Unstaked(msg.sender, unstakeAmount);
    }

    /**
    * @notice Claims accumulated staking rewards.
    * @dev Rewards can be claimed in two scenarios:
    *      1. After the presale has ended.
    *      2. During the migration phase, if early claiming has been explicitly enabled
    *         by the contract owner.
    *
    *      In both cases, rewards are distributed via the staking wallet and remain
    *      subject to the vesting logic defined in the LinxirToken contract.
    *
    *      This design ensures that rewards can be safely claimed and migrated
    *      to the Linxir native chain without breaking vesting guarantees.
    */

    function claimRewards() external {
        bool canClaim = token.presaleEndTime() > 0;
        bool canClaimDuringMigration = claimDuringMigrationEnabled;

        require(canClaim || canClaimDuringMigration, "Claim not available");

        _updateRewards(msg.sender);

        uint256 reward = stakes[msg.sender].rewardDebt;
        require(reward > 0, "No rewards");

        stakes[msg.sender].rewardDebt = 0;
        token.vestTransferFromWallet(token.stakingWallet(), msg.sender, reward);

        emit RewardClaimed(msg.sender, reward);
    }

    // -----------------------------------------------------
    // Internal reward logic
    // -----------------------------------------------------

    /**
     * @dev Updates the rewards for a given user.
     */
    function _updateRewards(address user) internal {
        StakeInfo storage stakeData = stakes[user];
        if (stakeData.amount == 0) return;

        uint256 reward = _calculateReward(stakeData);
        stakeData.rewardDebt += reward;

        // 🔒 Cristallizza sempre il periodo già calcolato
        stakeData.lastUpdate = rewardsStopped
            ? rewardsStopTime
            : token.currentTime();
    }

    /**
     * @dev Calculates pending reward since last update.
     */
    function _calculateReward(StakeInfo memory user) internal view returns (uint256) {
        if (user.amount == 0 || user.lastUpdate == 0) return 0;
        if (rewardsStopped && user.lastUpdate >= rewardsStopTime) {
            return 0;
        }
        uint256 to = rewardsStopped ? rewardsStopTime : token.currentTime();
        if (to <= user.lastUpdate) return 0;

        uint256 reward;
        uint256 cursor = user.lastUpdate;

        for (uint256 i = 0; i < 730 && cursor < to; ++i) {
            uint256 dayIndex = (cursor - stakingStartTime) / 1 days;
            uint256 dayEnd = stakingStartTime + (dayIndex + 1) * 1 days;
            if (dayEnd > to) dayEnd = to;

            uint256 apr = _getAPR(dayIndex);
            reward += _calculatePeriodReward(user.amount, apr, cursor, dayEnd);

            cursor = dayEnd;
        }

        return reward;
    }

    /**
     * @notice Returns APR (annual percentage rate) for a specific day.
     * @dev APR values are expressed in basis points (10000 = 100%).
     */
    function _getAPR(uint256 day) public pure returns (uint256) {
        // Day 0 → 29 : 1200% → ~50%
        // (120000 - 5000) / 30 = 3833 (precomputed)
        if (day < 30) {
            return 120000 - (day * 3833);
        }

        // Day 30 → 209 : 50% → 10%
        // (5000 - 1000) / 180 = 22 (precomputed)
        if (day < 210) {
            return 5000 - ((day - 30) * 22);
        }

        // Day >= 210 : fixed 10%
        return 1000;
    }

    /**
     * @dev Calculates reward for a specific period, applying booster if active.
     */
    function _calculatePeriodReward(
        uint256 amount,
        uint256 apr,
        uint256 start,
        uint256 end
    ) internal view returns (uint256) {
        uint256 baseReward = (amount * apr * (end - start)) / (365 days * 10000);
        uint256 boostedReward = baseReward;

        for (uint256 i = 0; i < boosterHistory.length; ++i) {
            BoosterPeriod memory booster = boosterHistory[i];

            // Trova la porzione di tempo in overlap col booster
            uint256 boostStart = start > booster.start ? start : booster.start;
            uint256 boostEnd = end < booster.end ? end : booster.end;

            if (boostEnd <= boostStart) continue;

            uint256 boostedDuration = boostEnd - boostStart;
            uint256 rewardInWindow = (amount * apr * boostedDuration) / (365 days * 10000);

            // Rimuovi la reward base per quella finestra e rimpiazzala con quella moltiplicata
            boostedReward -= rewardInWindow;
            boostedReward += rewardInWindow * booster.multiplier;
        }

        return boostedReward;
    }

    // -----------------------------------------------------
    // View functions
    // -----------------------------------------------------

    /**
     * @notice Returns total rewards for all users (for analytics).
     */
    function totalReward() external view onlyOwner returns (uint256 total) {
        for (uint256 i = 0; i < stakers.length; ++i) {
            StakeInfo memory user = stakes[stakers[i]];
            total += _calculateReward(user) + user.rewardDebt;
        }
    }

    /**
     * @notice Returns pending rewards for a user.
     */
    function getPendingRewards(address user) external view returns (uint256) {
        StakeInfo memory stakeData = stakes[user];
        return _calculateReward(stakeData) + stakeData.rewardDebt;
    }

    /**
     * @notice Returns staked amount for a user.
     */
    function getStakedAmount(address user) external view returns (uint256) {
        return stakes[user].amount;
    }

    /**
     * @notice Resets the staked amount of a user to zero.
     * @dev This function is used during cross-chain migration to avoid accounting inconsistencies on the L1 token.
     *      Can only be called by the LinxirToken contract after a successful migration.
     *      It does NOT trigger an unstake or claim; it simply clears the recorded stake.
     * @param user The address of the user whose staking amount should be reset.
     */
    function resetStaking(address user) external {
        require(msg.sender == address(token), "Only token can reset");
        stakes[user].amount = 0;
    }
}





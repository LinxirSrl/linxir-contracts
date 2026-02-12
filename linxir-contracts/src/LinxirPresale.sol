// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./LinxirToken.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title LinxirPresale
 * @notice This contract handles the presale of Linxir tokens (LXR),
 *         supporting payments in ETH and USDT, promo codes, and vesting integration.
 */
contract LinxirPresale is Ownable, ReentrancyGuard {

    using SafeERC20 for IERC20;

    // Reference to Linxir token (must implement vestTransferFromWallet logic)
    LinxirToken public immutable token;
    // USDT token used for purchase
    IERC20 public immutable usdt;

    // Address that receives funds raised
    address public treasury;
    // Chainlink ETH/USD price feed (8 decimals)
    AggregatorV3Interface public ethUsdPriceFeed;

    // Token decimals (LXR has 18 decimals)
    uint256 public constant TOKEN_DECIMALS = 1e18;

    /// @notice Maximum allowed staleness for Chainlink ETH/USD price
    uint256 public constant MAX_PRICE_DELAY = 10 minutes;

    // Max purchase in USD equivalent per transaction
    uint256 public maxPurchaseUSD = 1_000_000 * 1e18;

    // Struct to define each presale phase
    struct PresalePhase {
        uint256 startTokenId;
        uint256 endTokenId;
        uint256 startPriceUSD;
        uint256 endPriceUSD;
    }

    // Presale phases and global counter
    PresalePhase[] public phases;
    uint256 public totalSold;

    event TokensPurchased(
        address indexed buyer,
        uint256 tokenAmount,
        uint256 usdPaid,
        string paymentToken
    );

    constructor(
        address _token,
        address _usdt,
        address _treasury,
        address _ethUsdPriceFeed
    ) Ownable(msg.sender) {
        token = LinxirToken(_token);
        usdt = IERC20(_usdt);
        treasury = _treasury;
        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);

        // Initialize presale phases
        _addPhase(0 * TOKEN_DECIMALS, 64_000_000 * TOKEN_DECIMALS, 1e17, 13e16);    // $0.10 → $0.13
        _addPhase(64_000_000 * TOKEN_DECIMALS, 160_000_000 * TOKEN_DECIMALS, 13e16, 16e16); // $0.13 → $0.16
        _addPhase(160_000_000 * TOKEN_DECIMALS, 320_000_000 * TOKEN_DECIMALS, 16e16, 18e16); // $0.16 → $0.18
        _addPhase(320_000_000 * TOKEN_DECIMALS, 520_000_000 * TOKEN_DECIMALS, 18e16, 2e17);  // $0.18 → $0.20
        _addPhase(520_000_000 * TOKEN_DECIMALS, 800_000_000 * TOKEN_DECIMALS, 2e17, 22e16);  // $0.20 → $0.22
    }

    /// @notice Internal helper to push a new phase
    function _addPhase(
        uint256 start,
        uint256 end,
        uint256 startPrice,
        uint256 endPrice
    ) internal {
        phases.push(PresalePhase(start, end, startPrice, endPrice));
    }

    /// @notice Purchase tokens using ETH
    function buyWithETH() external payable nonReentrant {
        require(msg.value > 0, "Zero ETH");
        uint256 ethPriceUSD = getLatestETHPrice();
        uint256 usdAmount = (msg.value * ethPriceUSD) / 1e18;

        _processPurchase(msg.sender, usdAmount, "ETH");
        (bool success, ) = payable(treasury).call{value: msg.value}("");
        require(success, "ETH transfer failed");
    }

    /// @notice Purchase tokens using USDT
    function buyWithUSDT(uint256 usdtAmount) external nonReentrant {
        require(usdtAmount > 0, "Zero USDT");

        usdt.safeTransferFrom(msg.sender, treasury, usdtAmount);

        uint256 usdAmount = usdtAmount * 1e12; // USDT has 6 decimals → normalize to 1e18
        _processPurchase(msg.sender, usdAmount, "USDT");
    }


    /// @dev Core logic to process purchase amount across phases
    function _processPurchase(
        address buyer,
        uint256 usdAmount,
        string memory paymentToken
    ) internal {
        require(token.currentPresalePhase() > 0, "Presale not started");
        require(usdAmount <= maxPurchaseUSD, "Purchase too large");

        uint256 remaining = usdAmount;
        uint256 tokensToBuy = 0;

        for (uint256 i = 0; i < phases.length && remaining > 0; i++) {
            PresalePhase memory phase = phases[i];
            if (totalSold >= phase.endTokenId) continue;

            uint256 phaseSold = totalSold > phase.startTokenId ? totalSold - phase.startTokenId : 0;
            uint256 tokensAvailable = phase.endTokenId - totalSold;
            uint256 pricePerTokenUSD = getCurrentPrice(phase, phaseSold);

            uint256 possibleBuy = (remaining * TOKEN_DECIMALS) / pricePerTokenUSD;
            uint256 buyNow = possibleBuy > tokensAvailable ? tokensAvailable : possibleBuy;
            if (buyNow == 0) continue;

            uint256 cost = (buyNow * pricePerTokenUSD) / TOKEN_DECIMALS;
            remaining -= cost;
            tokensToBuy += buyNow;
            totalSold += buyNow;

            // Advance presale phase if needed
            uint8 currentPhase = token.currentPresalePhase();
            if (currentPhase > 0 && currentPhase < phases.length) {
                if (totalSold >= phases[currentPhase - 1].endTokenId) {
                    token.nextPresalePhase();
                }
            }
        }

        require(tokensToBuy > 0, "Nothing to buy");

        // Vest tokens from presale wallet
        token.vestTransferFromWallet(token.presaleWallet(), buyer, tokensToBuy);

        emit TokensPurchased(buyer, tokensToBuy, usdAmount, paymentToken);
    }

    /// @notice Calculate dynamic price based on phase and steps
    function getCurrentPrice(
        PresalePhase memory phase,
        uint256 phaseSold
    ) public pure returns (uint256) {
        uint256 steps = (phase.endTokenId - phase.startTokenId) / (100_000 * 1e18);
        if (steps <= 1) return phase.endPriceUSD;

        uint256 stepSize = (phase.endPriceUSD - phase.startPriceUSD) / (steps - 1);
        uint256 currentStep = phaseSold / (100_000 * 1e18);

        uint256 rawPrice = phase.startPriceUSD + (currentStep * stepSize);
        return rawPrice > phase.endPriceUSD ? phase.endPriceUSD : rawPrice;
    }

    /// @notice Get latest ETH/USD price from Chainlink (converted to 1e18)
    function getLatestETHPrice() public view returns (uint256) {
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = ethUsdPriceFeed.latestRoundData();

        require(price > 0, "Invalid price");
        require(updatedAt != 0, "Incomplete round");
        require(answeredInRound >= roundId, "Stale round");
        require(block.timestamp - updatedAt <= MAX_PRICE_DELAY, "Stale price");

        return uint256(price) * 1e10;
    }

    /// @notice Registers a manual token purchase (e.g. via Stripe, Apple Pay...)
    function registerTokenSale(address buyer, uint256 amount) external {
        require(msg.sender == address(token), "Not authorized");
        require(token.presaleEndTime() == 0, "Presale ended");

        totalSold += amount;
        emit TokensPurchased(buyer, amount, 0, "Manual");
    }

    /// @notice Update treasury address
    function setTreasury(address newTreasury) external onlyOwner {
        treasury = newTreasury;
    }

    /// @notice Set max USD equivalent purchase
    function setMaxPurchaseUSD(uint256 amount) external onlyOwner {
        maxPurchaseUSD = amount;
    }

    /// @dev Prevent direct ETH transfer
    receive() external payable {
        revert("Use buyWithETH");
    }

    /// @dev Fallback handler
    fallback() external payable {
        revert("Function not found");
    }
}



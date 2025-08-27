// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "src/access/OwnableBasic.sol";
import "src/erc721c/ERC721AC.sol";
import "src/programmable-royalties/BasicRoyalties.sol";
import "src/minting/MaxSupply.sol";
import "src/token/erc721/MetadataURI.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ERC721ACWithFactorySettings
 * @author Factory System
 * @notice ERC721AC with all Factory settings: MaxSupply, MetadataURI, BasicRoyalties
 * @dev Designed specifically for NFT Factory usage with complete feature set
 */
contract ERC721ACWithFactorySettings is 
    OwnableBasic, 
    ERC721AC, 
    BasicRoyalties, 
    MaxSupply,
    MetadataURI 
{

    using Strings for uint256;
    using SafeERC20 for IERC20;

    // Payment settings
    IERC20 public immutable usdcToken;
    address public immutable revenueRecipient;

    // Factory specific settings
    uint256 public mintPriceUSDC;
    uint256 public maxMintPerTx;
    uint256 public maxMintPerWallet;
    bool public publicMintEnabled;
    
    // Tracking mints per wallet
    mapping(address => uint256) public walletMints;

    // Events
    event MintSettingsUpdated(uint256 mintPrice, uint256 maxPerTx, uint256 maxPerWallet, bool publicEnabled);
    event PaidMint(address indexed buyer, uint256 quantity, uint256 totalPrice);

    constructor(
        address royaltyReceiver_,
        uint96 royaltyFeeNumerator_,
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        uint256 maxSupply_,
        uint256 mintPriceUSDC_,
        uint256 maxMintPerTx_,
        uint256 maxMintPerWallet_,
        bool publicMintEnabled_,
        address usdcToken_,
        address revenueRecipient_
    ) 
        ERC721AC(name_, symbol_) 
        BasicRoyalties(royaltyReceiver_, royaltyFeeNumerator_)
        MaxSupply(maxSupply_, 0) // 0 owner mints, all public
    {
        require(usdcToken_ != address(0), "Invalid USDC address");
        require(revenueRecipient_ != address(0), "Invalid revenue recipient");
        
        // Set payment settings
        usdcToken = IERC20(usdcToken_);
        revenueRecipient = revenueRecipient_;
        
        // Set metadata URI
        baseTokenURI = baseURI_;
        suffixURI = ".json";  // 🔧 자동으로 .json suffix 설정
        
        // Set factory settings
        mintPriceUSDC = mintPriceUSDC_;
        maxMintPerTx = maxMintPerTx_;
        maxMintPerWallet = maxMintPerWallet_;
        publicMintEnabled = publicMintEnabled_;
        
        emit MintSettingsUpdated(mintPriceUSDC_, maxMintPerTx_, maxMintPerWallet_, publicMintEnabled_);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721AC, ERC2981) returns (bool) {
        return ERC721AC.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }

    /// @notice Returns tokenURI with baseURI + tokenId
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if(!_exists(tokenId)) {
            revert URIQueryForNonexistentToken();
        }

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0
            ? string(abi.encodePacked(baseURI, tokenId.toString(), suffixURI))
            : "";
    }

    /// @dev Required to return baseTokenURI for tokenURI
    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    // Public mint function with USDC payment
    function mint(address to, uint256 quantity) external {
        require(publicMintEnabled, "Public mint not enabled");
        require(quantity > 0 && quantity <= maxMintPerTx, "Invalid quantity");
        require(walletMints[to] + quantity <= maxMintPerWallet, "Exceeds wallet limit");
        
        // Check max supply using ERC721A totalSupply
        _checkMaxSupply(quantity);
        
        // 💰 USDC 지불 로직 추가!
        uint256 totalPrice = mintPriceUSDC * quantity;
        if (totalPrice > 0) {
            usdcToken.safeTransferFrom(msg.sender, revenueRecipient, totalPrice);
            emit PaidMint(to, quantity, totalPrice);
        }
        
        // Update wallet mints
        walletMints[to] += quantity;
        
        // Mint tokens
        _mint(to, quantity);
    }

    function safeMint(address to, uint256 quantity) external {
        require(publicMintEnabled, "Public mint not enabled");
        require(quantity > 0 && quantity <= maxMintPerTx, "Invalid quantity");
        require(walletMints[to] + quantity <= maxMintPerWallet, "Exceeds wallet limit");
        
        // Check max supply using ERC721A totalSupply
        _checkMaxSupply(quantity);
        
        // 💰 USDC 지불 로직 추가!
        uint256 totalPrice = mintPriceUSDC * quantity;
        if (totalPrice > 0) {
            usdcToken.safeTransferFrom(msg.sender, revenueRecipient, totalPrice);
            emit PaidMint(to, quantity, totalPrice);
        }
        
        // Update wallet mints
        walletMints[to] += quantity;
        
        // Mint tokens
        _safeMint(to, quantity);
    }

    // Custom maxSupply check function using ERC721A totalSupply
    function _checkMaxSupply(uint256 quantity) internal view {
        uint256 maxSupplyCache = maxSupply();
        if (maxSupplyCache > 0) {
            if (totalSupply() + quantity > maxSupplyCache) {
                revert MaxSupplyBase__MaxSupplyExceeded();
            }
        }
    }

    // Owner functions
    function setMintSettings(
        uint256 mintPriceUSDC_,
        uint256 maxMintPerTx_,
        uint256 maxMintPerWallet_,
        bool publicMintEnabled_
    ) external {
        _requireCallerIsContractOwner();
        
        mintPriceUSDC = mintPriceUSDC_;
        maxMintPerTx = maxMintPerTx_;
        maxMintPerWallet = maxMintPerWallet_;
        publicMintEnabled = publicMintEnabled_;
        
        emit MintSettingsUpdated(mintPriceUSDC_, maxMintPerTx_, maxMintPerWallet_, publicMintEnabled_);
    }

    function burn(uint256 tokenId) external {
        _burn(tokenId);
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public {
        _requireCallerIsContractOwner();
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public {
        _requireCallerIsContractOwner();
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    // Override _mintToken for MaxSupply compatibility
    function _mintToken(address to, uint256 tokenId) internal override {
        _mint(to, 1);
    }
} 
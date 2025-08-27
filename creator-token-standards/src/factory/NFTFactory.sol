// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../erc721c/ERC721AC.sol";
import "../utils/PaymentSplitterInitializable.sol";
import "../examples/erc721ac/ERC721ACWithFactorySettings.sol";

contract NFTFactory is Ownable, ReentrancyGuard, Pausable {
    // 불변 변수들
    address public immutable splitterImplementation;
    address public immutable factoryCreator;  // Creator1 (Factory 배포자)
    address public immutable usdcToken;       // USDC 토큰 주소
    
    // 지분 설정
    uint256 public constant FACTORY_CREATOR_SHARE = 2;   // Creator1 지분 2%
    uint256 public constant NFT_CREATOR_SHARE = 98;      // Creator2 지분 98%
    
    // NFT 설정 구조체
    struct NFTSettings {
        string name;
        string symbol;
        string baseURI;
        uint256 maxSupply;
        uint256 mintPriceUSDC;      // USDC 기준 가격 (6 decimals)
        uint256 maxMintPerTx;       // 트랜잭션당 최대 민팅 수량
        uint256 maxMintPerWallet;   // 지갑당 최대 민팅 수량
        bool publicMintEnabled;      // 퍼블릭 민팅 활성화 여부
        uint96 royaltyFeeNumerator; // 로열티 % (500 = 5%)
    }
    
    // 매핑
    mapping(address => address) public nftToSplitter;
    mapping(address => bool) public isRegisteredNFT;
    
    // 이벤트
    event NFTDeployed(
        address indexed nftAddress,
        address indexed splitterAddress,
        address indexed creator,
        NFTSettings settings
    );
    
    constructor(
        address _splitterImplementation,
        address _usdcToken
    ) {
        require(_splitterImplementation != address(0), "Invalid splitter implementation");
        require(_usdcToken != address(0), "Invalid USDC address");
        
        splitterImplementation = _splitterImplementation;
        usdcToken = _usdcToken;
        factoryCreator = msg.sender;
    }
    
    function deployNFT(NFTSettings calldata settings) 
        external 
        nonReentrant 
        whenNotPaused 
        returns (address nftAddress, address splitterAddress) 
    {
        // 기본 검증
        require(settings.maxSupply > 0, "Invalid max supply");
        // mintPriceUSDC는 0 허용 (무료 민팅 가능)
        require(settings.maxMintPerTx > 0 && settings.maxMintPerTx <= 30, "Invalid maxMintPerTx");
        require(settings.maxMintPerWallet > 0, "Invalid maxMintPerWallet");
        require(bytes(settings.baseURI).length > 0, "Invalid baseURI");
        
        address nftCreator = msg.sender;
        
        // 1. PaymentSplitter 배포
        splitterAddress = _deploySplitter(nftCreator);
        
        // 2. NFT 컨트랙트 배포
        nftAddress = _deployNFT(settings, splitterAddress);
        
        // 매핑 업데이트
        nftToSplitter[nftAddress] = splitterAddress;
        isRegisteredNFT[nftAddress] = true;
        
        emit NFTDeployed(nftAddress, splitterAddress, nftCreator, settings);
        
        return (nftAddress, splitterAddress);
    }
    
    function _deploySplitter(address nftCreator) internal returns (address splitterAddress) {
        splitterAddress = Clones.clone(splitterImplementation);
        
        address[] memory payees = new address[](2);
        payees[0] = factoryCreator;  // Creator1
        payees[1] = nftCreator;      // Creator2
        
        uint256[] memory shares = new uint256[](2);
        shares[0] = FACTORY_CREATOR_SHARE;
        shares[1] = NFT_CREATOR_SHARE;
        
        PaymentSplitterInitializable(payable(splitterAddress)).initializePaymentSplitter(
            payees,
            shares
        );
    }
    
    function _deployNFT(NFTSettings calldata settings, address splitterAddress) internal returns (address) {
        return address(new ERC721ACWithFactorySettings(
            splitterAddress,              // 로열티 받을 주소 = PaymentSplitter
            settings.royaltyFeeNumerator, // 로열티 %
            settings.name,                // NFT 이름
            settings.symbol,              // NFT 심볼
            settings.baseURI,             // ✅ baseURI 전달!
            settings.maxSupply,           // ✅ maxSupply 전달!
            settings.mintPriceUSDC,       // ✅ mintPrice 전달!
            settings.maxMintPerTx,        // ✅ maxMintPerTx 전달!
            settings.maxMintPerWallet,    // ✅ maxMintPerWallet 전달!
            settings.publicMintEnabled,   // ✅ publicMintEnabled 전달!
            usdcToken,                    // 💰 USDC 토큰 주소 추가!
            splitterAddress               // 💰 수익 받을 주소 추가!
        ));  // 🔧 .json suffix는 생성자에서 자동 설정됨
    }
    
    // 긴급 정지 기능
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
} 
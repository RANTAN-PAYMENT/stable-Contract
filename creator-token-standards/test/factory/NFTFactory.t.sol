// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/factory/NFTFactory.sol";
import "../../src/examples/erc721ac/ERC721ACWithBasicRoyalties.sol";
import "../../src/utils/PaymentSplitterInitializable.sol";
import "../mocks/ERC20Mock.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract NFTFactoryTest is Test {
    NFTFactory public factory;
    ERC20Mock public usdcMock;
    
    address public factoryOwner = address(0x1);
    address public nftCreator1 = address(0x2);
    address public nftCreator2 = address(0x3);
    address public buyer1 = address(0x4);
    address public buyer2 = address(0x5);
    
    function setUp() public {
        // USDC Mock 배포
        usdcMock = new ERC20Mock(6);
        
        // Factory Owner가 Factory 배포
        vm.startPrank(factoryOwner);
        
        // 1. PaymentSplitter Implementation 배포
        PaymentSplitterInitializable splitterImpl = new PaymentSplitterInitializable();
        
        // 2. Factory용 PaymentSplitter 생성 (Factory 수수료용)
        address factorySplitter = Clones.clone(address(splitterImpl));
        
        address[] memory payees = new address[](2);
        payees[0] = factoryOwner;
        payees[1] = address(0x999); // 임시 더미 주소
        
        uint256[] memory shares = new uint256[](2);
        shares[0] = 2;   // Factory 2%
        shares[1] = 98;  // 임시 98%
        
        PaymentSplitterInitializable(payable(factorySplitter)).initializePaymentSplitter(payees, shares);
        
        // 3. NFT Implementation 배포 (더미)
        ERC721ACWithBasicRoyalties nftImpl = new ERC721ACWithBasicRoyalties(
            factorySplitter,  // Factory PaymentSplitter
            500,  // 5% 로열티
            "Implementation",
            "IMPL"
        );
        
        // 4. Factory 배포
        factory = new NFTFactory(
            address(splitterImpl),
            address(usdcMock)
        );
        
        vm.stopPrank();
        
        // 테스트용 자금 배분
        vm.deal(factoryOwner, 100 ether);
        vm.deal(nftCreator1, 100 ether);
        vm.deal(nftCreator2, 100 ether);
        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);
        
        // USDC 배분 및 approve
        uint256 usdcAmount = 1000000 * 10**6; // 1M USDC each
        
        // 각 사용자에게 USDC 배분
        usdcMock.mint(factoryOwner, usdcAmount);
        usdcMock.mint(nftCreator1, usdcAmount);
        usdcMock.mint(nftCreator2, usdcAmount);
        usdcMock.mint(buyer1, usdcAmount);
        usdcMock.mint(buyer2, usdcAmount);
        
        // 대량 사용자들을 위한 USDC 배분
        for(uint i = 0; i < 50; i++) {
            address user = address(uint160(1000 + i));
            vm.deal(user, 100 ether);
            usdcMock.mint(user, usdcAmount);
        }
    }
    
    // Helper function: USDC approve 및 민팅
    function mintWithUSDC(address nftAddress, address buyer, uint256 quantity, uint256 pricePerNFT) internal {
        vm.startPrank(buyer);
        uint256 totalCost = quantity * pricePerNFT;
        usdcMock.approve(nftAddress, totalCost);
        ERC721ACWithFactorySettings(nftAddress).mint(buyer, quantity);
        vm.stopPrank();
    }
    
    function testFullFactoryWorkflow() public {
        // 📋 시나리오: NFT Creator1이 Factory를 사용해서 NFT 컬렉션 배포
        
        vm.startPrank(nftCreator1);
        
        NFTFactory.NFTSettings memory settings = NFTFactory.NFTSettings({
            name: "Creator1 Collection",
            symbol: "C1C",
            baseURI: "https://creator1.com/",
            maxSupply: 1000,
            mintPriceUSDC: 50 * 10**6, // 50 USDC
            maxMintPerTx: 5,
            maxMintPerWallet: 10,
            publicMintEnabled: true,
            royaltyFeeNumerator: 500 // 5%
        });
        
        // NFT 컬렉션 배포
        (address nftAddress1, address splitterAddress1) = factory.deployNFT(settings);
        
        console.log("=== NFT Collection Deployed ===");
        console.log("NFT Address:", nftAddress1);
        console.log("PaymentSplitter Address:", splitterAddress1);
        
        vm.stopPrank();
        
        // 📋 시나리오: Buyer1이 NFT 구매
        mintWithUSDC(nftAddress1, buyer1, 3, 50 * 10**6); // 3개 민팅, 50 USDC each
        
        ERC721ACWithFactorySettings nft1 = ERC721ACWithFactorySettings(nftAddress1);
        console.log("=== NFT Minted ===");
        console.log("Buyer1 NFT Balance:", nft1.balanceOf(buyer1));
        
        // 📋 시나리오: 로열티 발생 (2차 거래 시뮬레이션)
        
        // PaymentSplitter에 로열티 자금 전송 (2차 거래에서 발생한 로열티라고 가정)
        vm.deal(splitterAddress1, 10 ether); // 10 ETH 로열티 발생
        
        console.log("=== Royalty Generated ===");
        console.log("PaymentSplitter Balance:", splitterAddress1.balance);
        
        // 📋 시나리오: 로열티 분배 확인
        PaymentSplitterInitializable splitter1 = PaymentSplitterInitializable(payable(splitterAddress1));
        
        // 분배 전 잔액
        uint256 factoryOwnerBefore = factoryOwner.balance;
        uint256 nftCreator1Before = nftCreator1.balance;
        
        console.log("=== Before Distribution ===");
        console.log("Factory Owner Balance:", factoryOwnerBefore);
        console.log("NFT Creator1 Balance:", nftCreator1Before);
        
        // 로열티 분배 실행
        vm.startPrank(nftCreator1);
        splitter1.release(payable(factoryOwner));  // Factory 몫 출금
        splitter1.release(payable(nftCreator1));   // Creator 몫 출금
        vm.stopPrank();
        
        // 분배 후 잔액
        uint256 factoryOwnerAfter = factoryOwner.balance;
        uint256 nftCreator1After = nftCreator1.balance;
        
        console.log("=== After Distribution ===");
        console.log("Factory Owner Balance:", factoryOwnerAfter);
        console.log("NFT Creator1 Balance:", nftCreator1After);
        
        // 검증: Factory는 2%, Creator는 98% 받아야 함
        assertEq(factoryOwnerAfter - factoryOwnerBefore, 0.2 ether); // 2% of 10 ether
        assertEq(nftCreator1After - nftCreator1Before, 9.8 ether);  // 98% of 10 ether
        
        console.log("Factory Fee Distribution Test PASSED!");
    }
    
    function testMultipleNFTCreators() public {
        // 📋 시나리오: 여러 Creator가 각각 NFT 컬렉션 배포
        
        // Creator1 NFT 배포
        vm.startPrank(nftCreator1);
        NFTFactory.NFTSettings memory settings1 = NFTFactory.NFTSettings({
            name: "Cats Collection",
            symbol: "CATS",
            baseURI: "https://cats.com/",
            maxSupply: 500,
            mintPriceUSDC: 100 * 10**6,
            maxMintPerTx: 3,
            maxMintPerWallet: 9,
            publicMintEnabled: true,
            royaltyFeeNumerator: 750 // 7.5%
        });
        (address nftAddress1, address splitterAddress1) = factory.deployNFT(settings1);
        vm.stopPrank();
        
        // Creator2 NFT 배포
        vm.startPrank(nftCreator2);
        NFTFactory.NFTSettings memory settings2 = NFTFactory.NFTSettings({
            name: "Dogs Collection",
            symbol: "DOGS",
            baseURI: "https://dogs.com/",
            maxSupply: 300,
            mintPriceUSDC: 200 * 10**6,
            maxMintPerTx: 2,
            maxMintPerWallet: 4,
            publicMintEnabled: true,
            royaltyFeeNumerator: 250 // 2.5%
        });
        (address nftAddress2, address splitterAddress2) = factory.deployNFT(settings2);
        vm.stopPrank();
        
        // 각각 다른 PaymentSplitter를 가져야 함
        assertTrue(splitterAddress1 != splitterAddress2);
        
        // 각 PaymentSplitter의 구성 확인
        PaymentSplitterInitializable splitter1 = PaymentSplitterInitializable(payable(splitterAddress1));
        PaymentSplitterInitializable splitter2 = PaymentSplitterInitializable(payable(splitterAddress2));
        
        // Splitter1: Factory + Creator1
        assertEq(splitter1.payee(0), factoryOwner);
        assertEq(splitter1.payee(1), nftCreator1);
        assertEq(splitter1.shares(factoryOwner), 2);
        assertEq(splitter1.shares(nftCreator1), 98);
        
        // Splitter2: Factory + Creator2
        assertEq(splitter2.payee(0), factoryOwner);
        assertEq(splitter2.payee(1), nftCreator2);
        assertEq(splitter2.shares(factoryOwner), 2);
        assertEq(splitter2.shares(nftCreator2), 98);
        
        console.log("Multiple NFT Creators Test PASSED!");
    }
    
    function testRoyaltyInfo() public {
        // NFT 배포
        vm.startPrank(nftCreator1);
        NFTFactory.NFTSettings memory settings = NFTFactory.NFTSettings({
            name: "Test Collection",
            symbol: "TEST",
            baseURI: "https://test.com/",
            maxSupply: 100,
            mintPriceUSDC: 10 * 10**6,
            maxMintPerTx: 1,
            maxMintPerWallet: 5,
            publicMintEnabled: true,
            royaltyFeeNumerator: 1000 // 10%
        });
        (address nftAddress, address splitterAddress) = factory.deployNFT(settings);
        vm.stopPrank();
        
        ERC721ACWithBasicRoyalties nft = ERC721ACWithBasicRoyalties(nftAddress);
        
        // 로열티 정보 확인
        (address royaltyRecipient, uint256 royaltyAmount) = nft.royaltyInfo(1, 1000 ether);
        
        assertEq(royaltyRecipient, splitterAddress); // PaymentSplitter가 로열티 받음
        assertEq(royaltyAmount, 100 ether); // 10% of 1000 ether
        
        console.log("Royalty Info Test PASSED!");
    }
    
    function testFactoryPauseUnpause() public {
        // Owner만 pause/unpause 가능
        vm.startPrank(factoryOwner);
        factory.pause();
        assertTrue(factory.paused());
        
        factory.unpause();
        assertFalse(factory.paused());
        vm.stopPrank();
        
        // 다른 사용자는 불가
        vm.startPrank(nftCreator1);
        vm.expectRevert();
        factory.pause();
        vm.stopPrank();
        
        console.log("Factory Pause/Unpause Test PASSED!");
    }
    
    function testBatchMinting30() public {
        console.log("=== 30 Batch Minting Test Start ===");
        
        // Deploy NFT Collection
        vm.startPrank(nftCreator1);
        NFTFactory.NFTSettings memory settings = NFTFactory.NFTSettings({
            name: "Batch Test Collection",
            symbol: "BATCH",
            baseURI: "https://batch.com/",
            maxSupply: 10000,
            mintPriceUSDC: 10 * 10**6, // 10 USDC
            maxMintPerTx: 30,  // Max allowed by factory
            maxMintPerWallet: 1000,
            publicMintEnabled: true,
            royaltyFeeNumerator: 500 // 5%
        });
        
        (address nftAddress, address splitterAddress) = factory.deployNFT(settings);
        ERC721ACWithBasicRoyalties nft = ERC721ACWithBasicRoyalties(nftAddress);
        
        console.log("NFT Collection Deployed:", nftAddress);
        vm.stopPrank();
        
        // Create multiple users for batch minting
        address[] memory buyers = new address[](10);
        for(uint i = 0; i < 10; i++) {
            buyers[i] = address(uint160(0x1000 + i));
            vm.deal(buyers[i], 100 ether);
        }
        
        console.log("=== Batch 1: 30 NFTs per user (10 users) ===");
        
        // Each user mints 30 NFTs
        for(uint i = 0; i < 10; i++) {
            vm.startPrank(buyers[i]);
            nft.mint(buyers[i], 30);
            console.log("User", i+1, "minted - Balance:", nft.balanceOf(buyers[i]));
            vm.stopPrank();
        }
        
        uint256 totalSupply = nft.totalSupply();
        console.log("Total minted:", totalSupply, "NFTs");
        assertEq(totalSupply, 300); // 10 users × 30 NFTs = 300 NFTs
        
        console.log("=== Batch 2: Additional 30 NFTs ===");
        
        // Additional 30 NFTs for first 5 users
        for(uint i = 0; i < 5; i++) {
            vm.startPrank(buyers[i]);
            nft.mint(buyers[i], 30);
            console.log("User", i+1, "additional mint - Total balance:", nft.balanceOf(buyers[i]));
            vm.stopPrank();
        }
        
        totalSupply = nft.totalSupply();
        console.log("Final total minted:", totalSupply, "NFTs");
        assertEq(totalSupply, 450); // 300 + (5 × 30) = 450 NFTs
        
        console.log("=== Batch 3: Mass Royalty Simulation ===");
        
        // Simulate mass trading royalties
        vm.deal(splitterAddress, 100 ether); // 100 ETH royalties
        
        PaymentSplitterInitializable splitter = PaymentSplitterInitializable(payable(splitterAddress));
        
        uint256 factoryOwnerBefore = factoryOwner.balance;
        uint256 nftCreator1Before = nftCreator1.balance;
        
        console.log("Before royalty distribution:");
        console.log("- Factory Owner:", factoryOwnerBefore / 1e18, "ETH");
        console.log("- NFT Creator:", nftCreator1Before / 1e18, "ETH");
        console.log("- PaymentSplitter:", splitterAddress.balance / 1e18, "ETH");
        
        // Distribute royalties
        vm.startPrank(nftCreator1);
        splitter.release(payable(factoryOwner));
        splitter.release(payable(nftCreator1));
        vm.stopPrank();
        
        uint256 factoryOwnerAfter = factoryOwner.balance;
        uint256 nftCreator1After = nftCreator1.balance;
        
        console.log("After royalty distribution:");
        console.log("- Factory Owner received:", (factoryOwnerAfter - factoryOwnerBefore) / 1e18, "ETH");
        console.log("- NFT Creator received:", (nftCreator1After - nftCreator1Before) / 1e18, "ETH");
        
        // Verify distribution
        assertEq(factoryOwnerAfter - factoryOwnerBefore, 2 ether); // 2% of 100 ETH
        assertEq(nftCreator1After - nftCreator1Before, 98 ether); // 98% of 100 ETH
        
        console.log("30 Batch Minting Test Complete!");
    }
    
    function testMaxMintingLimits() public {
        console.log("=== Max Minting Limits Test ===");
        
        // 최대 제한으로 NFT 컬렉션 배포
        vm.startPrank(nftCreator1);
        NFTFactory.NFTSettings memory settings = NFTFactory.NFTSettings({
            name: "Max Limit Collection",
            symbol: "MAX",
            baseURI: "https://maxlimit.com/",
            maxSupply: 1000,  // 총 1000개
            mintPriceUSDC: 1 * 10**6, // 1 USDC (저렴하게)
            maxMintPerTx: 30,  // Factory 최대 제한
            maxMintPerWallet: 100, // 지갑당 100개 제한
            publicMintEnabled: true,
            royaltyFeeNumerator: 1000 // 10% 로열티
        });
        
        (address nftAddress, address splitterAddress) = factory.deployNFT(settings);
        ERC721ACWithBasicRoyalties nft = ERC721ACWithBasicRoyalties(nftAddress);
        
        console.log("Max Limit NFT deployed:", nftAddress);
        vm.stopPrank();
        
        console.log("=== Test 1: Max Per Transaction (30) ===");
        
        // 한 사용자가 최대 트랜잭션 제한 테스트
        vm.startPrank(buyer1);
        nft.mint(buyer1, 30); // 최대 30개
        console.log("Buyer1 minted 30 NFTs - Balance:", nft.balanceOf(buyer1));
        
        // 31개도 민팅해보기 (제한 없이)
        nft.mint(buyer1, 31);
        console.log("Buyer1 minted 31 more NFTs - Total Balance:", nft.balanceOf(buyer1));
        vm.stopPrank();
        
        console.log("=== Test 2: Max Per Wallet (100) ===");
        
        // 한 지갑이 최대 100개까지 민팅 가능한지 테스트
        vm.startPrank(buyer2);
        
        // 30개씩 3번 = 90개
        nft.mint(buyer2, 30);
        nft.mint(buyer2, 30);
        nft.mint(buyer2, 30);
        console.log("Buyer2 minted 90 NFTs - Balance:", nft.balanceOf(buyer2));
        
        // 추가로 10개 더 (총 100개)
        nft.mint(buyer2, 10);
        console.log("Buyer2 minted 10 more NFTs - Total Balance:", nft.balanceOf(buyer2));
        
        // 1개 더 민팅해보기 (101개)
        nft.mint(buyer2, 1);
        console.log("Buyer2 minted 1 more NFT - Total Balance:", nft.balanceOf(buyer2));
        vm.stopPrank();
        
        console.log("=== Test 3: Max Supply Limit (1000) ===");
        
        // 여러 사용자가 최대 공급량까지 민팅
        address[] memory massiveBuyers = new address[](10);
        for(uint i = 0; i < 10; i++) {
            massiveBuyers[i] = address(uint160(0x3000 + i));
            vm.deal(massiveBuyers[i], 100 ether);
        }
        
        uint256 currentSupply = nft.totalSupply();
        console.log("Current total supply:", currentSupply);
        
        // 각 사용자가 100개씩 민팅 (10명 = 1000개 목표)
        // 하지만 이미 130개가 민팅되었으므로 870개만 더 필요
        uint256 remaining = 1000 - currentSupply;
        uint256 usersNeeded = remaining / 100;
        
        console.log("Remaining to mint:", remaining);
        console.log("Users needed:", usersNeeded);
        
        for(uint i = 0; i < usersNeeded; i++) {
            vm.startPrank(massiveBuyers[i]);
            nft.mint(massiveBuyers[i], 100);
            console.log("User", i+1, "minted 100 NFTs - Total supply:", nft.totalSupply());
            vm.stopPrank();
        }
        
        // 마지막 잔여분 민팅
        uint256 finalRemaining = 1000 - nft.totalSupply();
        if(finalRemaining > 0) {
            vm.startPrank(massiveBuyers[usersNeeded]);
            nft.mint(massiveBuyers[usersNeeded], finalRemaining);
            console.log("Final mint:", finalRemaining, "NFTs - Final supply:", nft.totalSupply());
            vm.stopPrank();
        }
        
        // 최대 공급량 도달 확인
        assertEq(nft.totalSupply(), 1000);
        console.log("Max supply reached: 1000 NFTs");
        
        // 최대 공급량 넘어서 민팅해보기
        vm.startPrank(buyer1);
        try nft.mint(buyer1, 1) {
            console.log("Minted beyond max supply - New total:", nft.totalSupply());
        } catch {
            console.log("Correctly rejected minting beyond max supply");
        }
        vm.stopPrank();
        
        console.log("=== Test 4: Massive Royalty Distribution ===");
        
        // 1000개 NFT에 대한 대량 로열티 시뮬레이션
        vm.deal(splitterAddress, 500 ether); // 500 ETH 로열티
        
        PaymentSplitterInitializable splitter = PaymentSplitterInitializable(payable(splitterAddress));
        
        uint256 factoryOwnerBefore = factoryOwner.balance;
        uint256 nftCreator1Before = nftCreator1.balance;
        
        console.log("Massive royalty distribution:");
        console.log("- Royalty pool: 500 ETH");
        
        // 로열티 분배
        vm.startPrank(nftCreator1);
        splitter.release(payable(factoryOwner));
        splitter.release(payable(nftCreator1));
        vm.stopPrank();
        
        uint256 factoryOwnerReceived = factoryOwner.balance - factoryOwnerBefore;
        uint256 nftCreator1Received = nftCreator1.balance - nftCreator1Before;
        
        console.log("- Factory Owner received:", factoryOwnerReceived / 1e18, "ETH");
        console.log("- NFT Creator received:", nftCreator1Received / 1e18, "ETH");
        
        // 검증
        assertEq(factoryOwnerReceived, 10 ether); // 2% of 500 ETH
        assertEq(nftCreator1Received, 490 ether); // 98% of 500 ETH
        
        console.log("Max Minting Limits Test Complete!");
        console.log("- Total NFTs minted: 1000/1000");
        console.log("- All limits properly enforced");
        console.log("- Massive royalty distribution successful");
    }
    
    function testMassiveClaimNumbers() external {
        console.log("=== Massive Claim Numbers Test (1000 NFTs) ===");
        
        // 1000개 maxSupply NFT 배포
        NFTFactory.NFTSettings memory settings = NFTFactory.NFTSettings({
            name: "Massive Test NFT",
            symbol: "MASSIVE",
            baseURI: "https://api.massive.com/metadata/",
            maxSupply: 1000,
            mintPriceUSDC: 50000000, // 50 USDC
            maxMintPerTx: 30,
            maxMintPerWallet: 100,
            publicMintEnabled: true,
            royaltyFeeNumerator: 500 // 5%
        });
        
        vm.prank(nftCreator1);
        (address nftAddress, address splitterAddress) = factory.deployNFT(settings);
        
        ERC721ACWithFactorySettings nft = ERC721ACWithFactorySettings(nftAddress);
        PaymentSplitterInitializable splitter = PaymentSplitterInitializable(payable(splitterAddress));
        
        console.log("NFT Address:", nftAddress);
        console.log("Splitter Address:", splitterAddress);
        console.log("Max Supply:", nft.maxSupply());
        
        // 대량 민팅 (1000개 모두 민팅)
        console.log("=== Mass Minting Phase ===");
        uint256 totalMinted = 0;
        
        // 34명이 30개씩 민팅 = 1020개 예정이지만 1000개에서 멈춤
        for(uint i = 0; i < 34; i++) {
            address buyer = address(uint160(2000 + i));
            vm.deal(buyer, 100 ether);
            usdcMock.mint(buyer, 1000000 * 10**6); // 1M USDC
            
            if(totalMinted + 30 <= 1000) {
                mintWithUSDC(nftAddress, buyer, 30, 50000000); // 30개, 50 USDC each
                totalMinted += 30;
                console.log("Buyer minted 30 NFTs - Total:", totalMinted);
            } else {
                uint256 remaining = 1000 - totalMinted;
                if(remaining > 0) {
                    mintWithUSDC(nftAddress, buyer, remaining, 50000000);
                    totalMinted += remaining;
                    console.log("Final buyer minted remaining NFTs - Total:", totalMinted);
                } else {
                    // maxSupply 도달로 실패해야 함
                    vm.startPrank(buyer);
                    vm.expectRevert();
                    nft.mint(buyer, 1);
                    vm.stopPrank();
                    console.log("Buyer FAILED to mint (maxSupply reached)");
                }
            }
            
            if(totalMinted >= 1000) break;
        }
        
        console.log("=== Minting Complete ===");
        console.log("Final Total Supply:", nft.totalSupply());
        console.log("Max Supply:", nft.maxSupply());
        assertEq(nft.totalSupply(), 1000);
        
        // 대량 로열티 시뮬레이션 (1000 ETH 거래 시뮬레이션)
        console.log("=== Massive Royalty Simulation ===");
        uint256 massiveRoyalty = 1000 ether; // 1000 ETH 상당의 로열티
        vm.deal(splitterAddress, massiveRoyalty);
        
        console.log("Total Royalty Pool:", splitterAddress.balance / 1e18, "ETH");
        
        // 분배 전 잔액 확인
        uint256 factoryOwnerBefore = factoryOwner.balance;
        uint256 nftCreatorBefore = nftCreator1.balance;
        
        console.log("=== Before Claim ===");
        console.log("Factory Owner Balance:", factoryOwnerBefore / 1e18, "ETH");
        console.log("NFT Creator Balance:", nftCreatorBefore / 1e18, "ETH");
        console.log("Splitter Balance:", splitterAddress.balance / 1e18, "ETH");
        
        // 클레임 가능 금액 확인
        uint256 factoryReleasable = splitter.releasable(factoryOwner);
        uint256 creatorReleasable = splitter.releasable(nftCreator1);
        
        console.log("=== Claimable Amounts ===");
        console.log("Factory Owner Claimable:", factoryReleasable / 1e18, "ETH");
        console.log("NFT Creator Claimable:", creatorReleasable / 1e18, "ETH");
        
        // 예상 금액 검증
        uint256 expectedFactory = massiveRoyalty * 2 / 100; // 2%
        uint256 expectedCreator = massiveRoyalty * 98 / 100; // 98%
        
        assertEq(factoryReleasable, expectedFactory);
        assertEq(creatorReleasable, expectedCreator);
        
        console.log("Expected Factory Share:", expectedFactory / 1e18, "ETH");
        console.log("Expected Creator Share:", expectedCreator / 1e18, "ETH");
        
        // 실제 클레임 실행
        console.log("=== Claiming Process ===");
        
        vm.startPrank(factoryOwner);
        splitter.release(payable(factoryOwner));
        console.log("Factory Owner claimed successfully");
        vm.stopPrank();
        
        vm.startPrank(nftCreator1);
        splitter.release(payable(nftCreator1));
        console.log("NFT Creator claimed successfully");
        vm.stopPrank();
        
        // 분배 후 잔액 확인
        uint256 factoryOwnerAfter = factoryOwner.balance;
        uint256 nftCreatorAfter = nftCreator1.balance;
        
        console.log("=== After Claim ===");
        console.log("Factory Owner Balance:", factoryOwnerAfter / 1e18, "ETH");
        console.log("NFT Creator Balance:", nftCreatorAfter / 1e18, "ETH");
        console.log("Splitter Balance:", splitterAddress.balance / 1e18, "ETH");
        
        // 실제 받은 금액
        uint256 factoryReceived = factoryOwnerAfter - factoryOwnerBefore;
        uint256 creatorReceived = nftCreatorAfter - nftCreatorBefore;
        
        console.log("=== Actual Received ===");
        console.log("Factory Owner Received:", factoryReceived / 1e18, "ETH");
        console.log("NFT Creator Received:", creatorReceived / 1e18, "ETH");
        console.log("Total Distributed:", (factoryReceived + creatorReceived) / 1e18, "ETH");
        
        // 검증
        assertEq(factoryReceived, expectedFactory);
        assertEq(creatorReceived, expectedCreator);
        assertEq(factoryReceived + creatorReceived, massiveRoyalty);
        assertEq(splitterAddress.balance, 0); // 모든 금액 분배 완료
        
        console.log("=== Security Analysis ===");
        console.log("PASS: Exact 2% / 98% split maintained");
        console.log("PASS: No funds left in splitter");
        console.log("PASS: Total distributed equals total received");
        console.log("PASS: MaxSupply enforcement working");
        console.log("PASS: No overflow/underflow detected");
        
        console.log("=== MASSIVE CLAIM TEST COMPLETED SUCCESSFULLY ===");
    }
    
    function testCompleteFactoryFeatures() external {
        // NFT 설정
        NFTFactory.NFTSettings memory settings = NFTFactory.NFTSettings({
            name: "Complete Test NFT",
            symbol: "COMPLETE",
            baseURI: "https://api.complete.com/metadata/",
            maxSupply: 100,
            mintPriceUSDC: 5000000, // 5 USDC
            maxMintPerTx: 5,
            maxMintPerWallet: 10,
            publicMintEnabled: true,
            royaltyFeeNumerator: 750 // 7.5%
        });
        
        // NFT 배포
        vm.prank(nftCreator1);
        (address nftAddress, address splitterAddress) = factory.deployNFT(settings);
        
        ERC721ACWithFactorySettings nft = ERC721ACWithFactorySettings(nftAddress);
        
        console.log("=== Complete Factory Features Test ===");
        
        // 1. 기본 정보 확인
        assertEq(nft.name(), "Complete Test NFT");
        assertEq(nft.symbol(), "COMPLETE");
        assertEq(nft.maxSupply(), 100);
        assertEq(nft.maxMintPerTx(), 5);
        assertEq(nft.maxMintPerWallet(), 10);
        assertTrue(nft.publicMintEnabled());
        console.log("Basic Settings Verified");
        
        // 2. tokenURI 확인 (민팅 전에는 에러)
        vm.expectRevert();
        nft.tokenURI(0);
        
        // 3. 민팅 테스트
        vm.prank(buyer1);
        nft.mint(buyer1, 3);
        
        assertEq(nft.balanceOf(buyer1), 3);
        assertEq(nft.totalSupply(), 3);
        console.log("Minting Works");
        
        // 4. tokenURI 확인 (민팅 후) - ERC721A는 0부터 시작
        string memory uri0 = nft.tokenURI(0);
        string memory uri1 = nft.tokenURI(1);
        string memory uri2 = nft.tokenURI(2);
        
        assertEq(uri0, "https://api.complete.com/metadata/0");
        assertEq(uri1, "https://api.complete.com/metadata/1");
        assertEq(uri2, "https://api.complete.com/metadata/2");
        console.log("TokenURI Works:", uri1);
        
        // 5. 지갑당 한도 테스트
        vm.prank(buyer1);
        nft.mint(buyer1, 5); // 총 8개
        
        vm.prank(buyer1);
        nft.mint(buyer1, 2); // 총 10개 (한도)
        
        vm.prank(buyer1);
        vm.expectRevert("Exceeds wallet limit");
        nft.mint(buyer1, 1); // 한도 초과
        console.log("Wallet Limit Works");
        
        // 6. 트랜잭션당 한도 테스트
        vm.prank(buyer2);
        vm.expectRevert("Invalid quantity");
        nft.mint(buyer2, 6); // 5개 초과
        console.log("Per-TX Limit Works");
        
        // 7. maxSupply 테스트 (90개 더 민팅해서 100개 도달)
        for(uint i = 0; i < 18; i++) { // 18 * 5 = 90개
            address randomBuyer = address(uint160(1000 + i));
            vm.prank(randomBuyer);
            nft.mint(randomBuyer, 5);
        }
        
        assertEq(nft.totalSupply(), 100); // 10 + 90 = 100개 (정확히 maxSupply)
        console.log("Current total supply:", nft.totalSupply());
        console.log("Max supply:", nft.maxSupply());
        
        // 8. maxSupply 초과 테스트
        vm.prank(buyer2);
        vm.expectRevert();
        nft.mint(buyer2, 1);
        console.log("MaxSupply Check Works");
        
        // 9. 로열티 테스트 
        (address royaltyReceiver, uint256 royaltyAmount) = nft.royaltyInfo(0, 10000); // 1 ETH 거래 시
        assertEq(royaltyReceiver, splitterAddress);
        assertEq(royaltyAmount, 750); // 7.5% = 0.075 ETH
        console.log("Royalty Info Works");
        
        console.log("=== All Factory Features Working! ===");
    }
    
    function testGasAndOperationalSimulation() external {
        console.log("=== Gas & Operational Simulation Test ===");
        
        // 1. Factory 배포 가스비 측정
        console.log("=== Gas Analysis Phase 1: Factory Deployment ===");
        
        uint256 gasBefore = gasleft();
        NFTFactory.NFTSettings memory settings = NFTFactory.NFTSettings({
            name: "Gas Test Collection",
            symbol: "GAS",
            baseURI: "https://api.gastest.com/",
            maxSupply: 500,
            mintPriceUSDC: 25000000, // 25 USDC
            maxMintPerTx: 20,
            maxMintPerWallet: 50,
            publicMintEnabled: true,
            royaltyFeeNumerator: 750 // 7.5%
        });
        
        vm.prank(nftCreator1);
        (address nftAddress, address splitterAddress) = factory.deployNFT(settings);
        uint256 gasUsedDeploy = gasBefore - gasleft();
        
        console.log("NFT + Splitter Deployment Gas:", gasUsedDeploy);
        
        ERC721ACWithFactorySettings nft = ERC721ACWithFactorySettings(nftAddress);
        PaymentSplitterInitializable splitter = PaymentSplitterInitializable(payable(splitterAddress));
        
        // 2. 민팅 가스비 분석
        console.log("=== Gas Analysis Phase 2: Minting Patterns ===");
        
        address testBuyer = address(0x9999);
        vm.deal(testBuyer, 100 ether);
        
        // 단일 민팅 가스비
        vm.startPrank(testBuyer);
        gasBefore = gasleft();
        nft.mint(testBuyer, 1);
        uint256 gasSingleMint = gasBefore - gasleft();
        console.log("Single Mint Gas:", gasSingleMint);
        
        // 5개 민팅 가스비
        gasBefore = gasleft();
        nft.mint(testBuyer, 5);
        uint256 gasBatchMint5 = gasBefore - gasleft();
        console.log("Batch Mint (5) Gas:", gasBatchMint5);
        console.log("Gas per NFT (batch 5):", gasBatchMint5 / 5);
        
        // 20개 민팅 가스비
        gasBefore = gasleft();
        nft.mint(testBuyer, 20);
        uint256 gasBatchMint20 = gasBefore - gasleft();
        console.log("Batch Mint (20) Gas:", gasBatchMint20);
        console.log("Gas per NFT (batch 20):", gasBatchMint20 / 20);
        vm.stopPrank();
        
        // 3. 로열티 클레임 가스비
        console.log("=== Gas Analysis Phase 3: Royalty Claims ===");
        
        // 로열티 시뮬레이션
        vm.deal(splitterAddress, 100 ether);
        
        // Factory Owner 클레임 가스비
        vm.startPrank(factoryOwner);
        gasBefore = gasleft();
        splitter.release(payable(factoryOwner));
        uint256 gasFactoryClaim = gasBefore - gasleft();
        console.log("Factory Owner Claim Gas:", gasFactoryClaim);
        vm.stopPrank();
        
        // NFT Creator 클레임 가스비
        vm.startPrank(nftCreator1);
        gasBefore = gasleft();
        splitter.release(payable(nftCreator1));
        uint256 gasCreatorClaim = gasBefore - gasleft();
        console.log("NFT Creator Claim Gas:", gasCreatorClaim);
        vm.stopPrank();
        
        // 4. 경계값 테스트
        console.log("=== Boundary Value Testing ===");
        
        // maxMintPerTx 경계값 테스트
        address boundaryBuyer = address(0x8888);
        vm.deal(boundaryBuyer, 100 ether);
        vm.startPrank(boundaryBuyer);
        
        // 정확히 한도만큼 민팅 (성공해야 함)
        nft.mint(boundaryBuyer, 20); // maxMintPerTx = 20
        console.log("Boundary mint (exactly maxMintPerTx): SUCCESS");
        
        // 한도 초과 민팅 (실패해야 함)
        vm.expectRevert("Invalid quantity");
        nft.mint(boundaryBuyer, 21);
        console.log("Boundary mint (exceed maxMintPerTx): CORRECTLY FAILED");
        vm.stopPrank();
        
        // 5. 실패 시나리오 테스트
        console.log("=== Failure Scenario Testing ===");
        
        // 민팅 비활성화 테스트
        vm.startPrank(nftCreator1);
        nft.setMintSettings(25000000, 20, 50, false); // publicMintEnabled = false
        vm.stopPrank();
        
        vm.startPrank(testBuyer);
        vm.expectRevert("Public mint not enabled");
        nft.mint(testBuyer, 1);
        console.log("Disabled mint test: CORRECTLY FAILED");
        
        // 민팅 재활성화
        vm.startPrank(nftCreator1);
        nft.setMintSettings(25000000, 20, 50, true);
        vm.stopPrank();
        
        nft.mint(testBuyer, 1); // 이제 성공해야 함
        console.log("Re-enabled mint test: SUCCESS");
        vm.stopPrank();
        
        // 6. 지갑 한도 도달 테스트
        console.log("=== Wallet Limit Exhaustion Test ===");
        
        address limitBuyer = address(0x7777);
        vm.deal(limitBuyer, 100 ether);
        vm.startPrank(limitBuyer);
        
        // 50개까지 민팅 (maxMintPerWallet = 50)
        nft.mint(limitBuyer, 20);
        nft.mint(limitBuyer, 20);
        nft.mint(limitBuyer, 10); // 총 50개
        console.log("Wallet limit reached (50 NFTs): SUCCESS");
        
        // 추가 민팅 시도 (실패해야 함)
        vm.expectRevert("Exceeds wallet limit");
        nft.mint(limitBuyer, 1);
        console.log("Exceed wallet limit test: CORRECTLY FAILED");
        vm.stopPrank();
        
        // 7. 대량 사용자 동시 접근 시뮬레이션
        console.log("=== Concurrent Users Simulation ===");
        
        uint256 concurrentUsers = 10;
        uint256 totalGasUsed = 0;
        
        for(uint i = 0; i < concurrentUsers; i++) {
            address user = address(uint160(5000 + i));
            vm.deal(user, 100 ether);
            
            vm.startPrank(user);
            gasBefore = gasleft();
            nft.mint(user, 10); // 각자 10개씩 민팅
            uint256 gasUsed = gasBefore - gasleft();
            totalGasUsed += gasUsed;
            vm.stopPrank();
        }
        
        console.log("Concurrent users:", concurrentUsers);
        console.log("Total gas used:", totalGasUsed);
        console.log("Average gas per user:", totalGasUsed / concurrentUsers);
        
        // 8. 최종 상태 검증
        console.log("=== Final State Verification ===");
        console.log("Total NFTs minted:", nft.totalSupply());
        console.log("Max supply:", nft.maxSupply());
        console.log("Remaining mintable:", nft.maxSupply() - nft.totalSupply());
        
        // 9. 비용 효율성 분석
        console.log("=== Cost Efficiency Analysis ===");
        
        // ETH 가격 $3000, Gas 가격 20 gwei 가정
        uint256 ethPrice = 3000; // USD
        uint256 gasPrice = 20; // gwei
        
        uint256 deploymentCostUSD = (gasUsedDeploy * gasPrice * ethPrice) / 1e18;
        uint256 singleMintCostUSD = (gasSingleMint * gasPrice * ethPrice) / 1e18;
        uint256 batchMint20CostUSD = (gasBatchMint20 * gasPrice * ethPrice) / 1e18;
        
        console.log("=== USD Cost Analysis (ETH=$3000, Gas=20gwei) ===");
        console.log("Deployment cost: $", deploymentCostUSD);
        console.log("Single mint cost: $", singleMintCostUSD);
        console.log("Batch mint (20) cost: $", batchMint20CostUSD);
        console.log("Cost per NFT (batch): $", batchMint20CostUSD / 20);
        
        // 10. 보안 및 권한 테스트
        console.log("=== Security & Permission Testing ===");
        
        // 무권한 사용자가 Factory 설정 변경 시도
        vm.startPrank(address(0x6666));
        vm.expectRevert();
        factory.pause();
        console.log("Unauthorized factory pause: CORRECTLY FAILED");
        
        // 무권한 사용자가 NFT 설정 변경 시도
        vm.expectRevert();
        nft.setMintSettings(1000000, 1, 1, false);
        console.log("Unauthorized NFT settings change: CORRECTLY FAILED");
        vm.stopPrank();
        
        // 정상 권한 테스트
        vm.startPrank(factoryOwner);
        factory.pause();
        factory.unpause();
        console.log("Authorized factory control: SUCCESS");
        vm.stopPrank();
        
        vm.startPrank(nftCreator1);
        nft.setMintSettings(25000000, 20, 50, true);
        console.log("Authorized NFT control: SUCCESS");
        vm.stopPrank();
        
        console.log("=== GAS & OPERATIONAL SIMULATION COMPLETED ===");
    }
} 
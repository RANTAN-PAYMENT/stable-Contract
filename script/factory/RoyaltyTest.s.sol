// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../../src/examples/erc721ac/ERC721ACWithFactorySettings.sol";
import "../../src/utils/PaymentSplitterInitializable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

contract RoyaltyTest is Script {
    function run() external {
        // NFT 컬렉션 주소
        address nftAddress = 0xbDBe9c5469a16AB6866443F3F08865d9078e3225;
        address paymentSplitterAddress = 0x6534E78271f21a0Bc21E33707871823fec19Ab04;
        
        ERC721ACWithFactorySettings nft = ERC721ACWithFactorySettings(nftAddress);
        PaymentSplitterInitializable splitter = PaymentSplitterInitializable(payable(paymentSplitterAddress));
        
        uint256 nftCreatorPrivateKey = vm.envUint("NFT_CREATOR_PRIVATE_KEY");
        address nftCreator = vm.addr(nftCreatorPrivateKey);
        
        // 가상의 구매자 주소들
        address buyer1 = address(0x1111);
        address buyer2 = address(0x2222);
        
        console.log("=== NFT Royalty Test ===");
        console.log("NFT Contract:", nftAddress);
        console.log("PaymentSplitter:", paymentSplitterAddress);
        console.log("NFT Creator:", nftCreator);
        console.log("Buyer1:", buyer1);
        console.log("Buyer2:", buyer2);
        
        // ERC2981 지원 확인
        bool supportsERC2981 = nft.supportsInterface(type(IERC2981).interfaceId);
        console.log("Supports ERC2981:", supportsERC2981);
        
        // 토큰 0의 로열티 정보 확인
        uint256 tokenId = 0;
        uint256 salePrice = 1 ether; // 1 ETH 판매 가격
        
        (address royaltyReceiver, uint256 royaltyAmount) = nft.royaltyInfo(tokenId, salePrice);
        
        console.log("=== Royalty Info for Token", tokenId, "===");
        console.log("Sale Price:", salePrice);
        console.log("Royalty Receiver:", royaltyReceiver);
        console.log("Royalty Amount:", royaltyAmount);
        console.log("Royalty Percentage:", (royaltyAmount * 100) / salePrice, "%");
        
        // 다른 판매 가격들로 테스트
        uint256[] memory testPrices = new uint256[](5);
        testPrices[0] = 0.1 ether;
        testPrices[1] = 0.5 ether;
        testPrices[2] = 1 ether;
        testPrices[3] = 5 ether;
        testPrices[4] = 10 ether;
        
        console.log("=== Royalty Calculation Test ===");
        for(uint i = 0; i < testPrices.length; i++) {
            (address receiver, uint256 amount) = nft.royaltyInfo(tokenId, testPrices[i]);
            console.log("Price:", testPrices[i] / 1e18, "ETH, Royalty:", amount, "wei, Receiver:", receiver);
        }
        
        vm.startBroadcast(nftCreatorPrivateKey);
        
        // 2차 거래 로열티 시뮬레이션
        console.log("=== Simulating Secondary Sale Royalty ===");
        
        // PaymentSplitter 잔액 확인 (출금 전)
        uint256 splitterBalanceBefore = paymentSplitterAddress.balance;
        console.log("PaymentSplitter ETH Balance Before:", splitterBalanceBefore);
        
        // 로열티를 PaymentSplitter에 직접 전송 (2차 거래에서 발생한 로열티라고 가정)
        uint256 royaltyPayment = 0.05 ether; // 0.05 ETH 로열티
        (bool success,) = paymentSplitterAddress.call{value: royaltyPayment}("");
        require(success, "Royalty payment failed");
        
        console.log("Sent", royaltyPayment, "ETH as royalty to PaymentSplitter");
        
        // PaymentSplitter 잔액 확인 (입금 후)
        uint256 splitterBalanceAfter = paymentSplitterAddress.balance;
        console.log("PaymentSplitter ETH Balance After:", splitterBalanceAfter);
        
        // Factory Creator와 NFT Creator 잔액 확인 (분배 전)
        address factoryCreator = 0x70F24aA566adBa0eCeE40bc092A82F270377092A;
        uint256 factoryCreatorBalanceBefore = factoryCreator.balance;
        uint256 nftCreatorBalanceBefore = nftCreator.balance;
        
        console.log("=== Before Royalty Distribution ===");
        console.log("Factory Creator ETH Balance:", factoryCreatorBalanceBefore);
        console.log("NFT Creator ETH Balance:", nftCreatorBalanceBefore);
        
        // 로열티 분배
        uint256 factoryCreatorReleasable = splitter.releasable(factoryCreator);
        uint256 nftCreatorReleasable = splitter.releasable(nftCreator);
        
        console.log("=== Releasable ETH Amounts ===");
        console.log("Factory Creator Releasable:", factoryCreatorReleasable);
        console.log("NFT Creator Releasable:", nftCreatorReleasable);
        
        if (factoryCreatorReleasable > 0) {
            splitter.release(payable(factoryCreator));
            console.log("Released", factoryCreatorReleasable, "ETH to Factory Creator");
        }
        
        if (nftCreatorReleasable > 0) {
            splitter.release(payable(nftCreator));
            console.log("Released", nftCreatorReleasable, "ETH to NFT Creator");
        }
        
        // 분배 후 잔액 확인
        uint256 factoryCreatorBalanceAfter = factoryCreator.balance;
        uint256 nftCreatorBalanceAfter = nftCreator.balance;
        
        console.log("=== After Royalty Distribution ===");
        console.log("Factory Creator ETH Balance:", factoryCreatorBalanceAfter);
        console.log("NFT Creator ETH Balance:", nftCreatorBalanceAfter);
        
        console.log("=== Royalty Distribution Summary ===");
        console.log("Factory Creator Received:", factoryCreatorBalanceAfter - factoryCreatorBalanceBefore, "ETH");
        console.log("NFT Creator Received:", nftCreatorBalanceAfter - nftCreatorBalanceBefore, "ETH");
        console.log("Total Distributed:", (factoryCreatorBalanceAfter - factoryCreatorBalanceBefore) + (nftCreatorBalanceAfter - nftCreatorBalanceBefore), "ETH");
        
        vm.stopBroadcast();
    }
} 
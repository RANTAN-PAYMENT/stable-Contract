#!/bin/bash

# Load environment variables
source .env

# Deploy to the specified network
forge script script/factory/DeployNFTFactory.s.sol:DeployNFTFactory \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    -vvvv
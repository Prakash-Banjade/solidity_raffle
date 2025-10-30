-include .env

install-deps:
	forge install smartcontractkit/chainlink-brownie-contracts &&
	forge install tramsmissions11/solmate &&
	forge install Cyfrin/foundry-devops

deploy-mainnet:
	forge script script/DeployFundMe.s.sol:DeployFundMe --rpc-url $(MAINNET_RPC_URL) --private-key $(DEPLOYER_PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

fund-subscription:
	forge script script/Interactions.s.sol:FundSubscription --rpc-url $(SEPOLIA_RPC_URL) --account myaccount --broadcast -vvvv
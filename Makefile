script-local:
	forge script script/Clusters.s.sol

sim-deploy-testnet:
	forge script -vvvvv script/Testnet.s.sol --sig "run()"

deploy-testnet:
	forge script -vvv script/Testnet.s.sol --sig "run()" --broadcast

deploy-beta-testnet-hub:
	forge script -vvv script/VanityMining.s.sol --sig "testInitiate()" --fork-url ${RPC_URL} --private-key ${PK} --broadcast

sim-vanity:
	forge script -vvv script/VanityMining.s.sol --sig "deployAndUpgrade()" --fork-url ${RPC_URL} --private-key ${PK}  --broadcast --verify --delay 30 --etherscan-api-key ${ETHERSCAN_API_KEY}
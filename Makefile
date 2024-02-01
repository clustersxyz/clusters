script-local:
	forge script script/Clusters.s.sol

sim-deploy-testnet:
	forge script -vvvvv script/Testnet.s.sol --sig "run()"

deploy-testnet:
	forge script -vvv script/Testnet.s.sol --sig "run()" --broadcast

deploy-beta-hub:
	forge script -vvv script/VanityMining.s.sol --sig "configureHub()" --fork-url ${ETHEREUM_RPC_URL} --private-key ${PK} --broadcast --verify --delay 30 --etherscan-api-key ${ETHERSCAN_API_KEY}

deploy-beta-initiator:
	forge script -vvv script/VanityMining.s.sol --sig "upgradeInitiator()" --fork-url ${BASE_RPC_URL} --private-key ${PK} --broadcast --verify --delay 30 --etherscan-api-key ${BASESCAN_API_KEY}

do-initiate:
	forge script -vvv script/VanityMining.s.sol --sig "doInitiate()" --fork-url ${POLYGON_RPC_URL} --private-key ${PK} --broadcast

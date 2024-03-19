script-local:
	forge script script/Clusters.s.sol

sim-deploy-testnet:
	forge script -vvvvv script/Testnet.s.sol --sig "run()"

deploy-testnet:
	forge script -vvv script/Testnet.s.sol --sig "run()" --broadcast

call-beta-hub:
	# For live deployment, add --broadcast --verify --delay 30 --etherscan-api-key ${ETHERSCAN_API_KEY}
	forge script -vvv script/DeployBeta.s.sol --sig "upgradeHub()" --fork-url ${ETHEREUM_RPC_URL} --private-key ${PK}

call-beta-initiator:
	forge script -vvv script/DeployBeta.s.sol --sig "upgradeInitiator()" --fork-url ${BASE_RPC_URL} --private-key ${PK}

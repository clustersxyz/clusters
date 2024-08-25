script-local:
	forge script script/Clusters.s.sol

sim-deploy-testnet:
	forge script -vvvvv script/Testnet.s.sol --sig "run()"

deploy-testnet:
	forge script -vvv script/Testnet.s.sol --sig "run()" --broadcast

call-beta-hub:
	# For live deployment, add --broadcast --verify --delay 30 --etherscan-api-key ${ETHERSCAN_API_KEY}
	forge script -vvvvv script/DeployBeta.s.sol --sig "configureHub()" --fork-url ${ETHEREUM_RPC_URL} --private-key ${PK} --broadcast
	# forge script -vvv script/DeployBeta.s.sol --sig "upgradeInitiator()" --fork-url ${TAIKO_RPC_URL} --private-key ${PK}

call-batch-refund:
	forge script -vvv script/BatchInteraction.s.sol --sig "run()"

call-beta-initiator:
	forge script -vvv script/DeployBeta.s.sol --sig "doInitiate()" --fork-url ${TAIKO_RPC_URL} --private-key ${PK} -vvv
	# forge script -vvv script/SetDVNConfig.s.sol --sig "setDestReceiveConfig()" -vvv

verify:
	forge verify-contract 0xa8a8157F4ed368F9d15468670253aC00c5661Ba9 src/InitiatorBeta.sol:InitiatorBeta --chain 167000  --etherscan-api-key ${ETHERSCAN_API_KEY} --retries 5 --delay 30 --watch


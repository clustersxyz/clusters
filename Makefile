script-local:
	forge script script/Clusters.s.sol

sim-deploy-testnet:
	forge script -vvvvv script/Testnet.s.sol --sig "run()"

deploy-testnet:
	forge script -vvv script/Testnet.s.sol --sig "run()" --broadcast
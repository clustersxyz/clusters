script-local:
	forge script script/Clusters.s.sol

sim-deploy-testnet:
	forge script -vvvvv script/Testnet.s.sol --sig "run()"

deploy-testnet:
	forge script -vvv script/Testnet.s.sol --sig "run()" --broadcast

sim-vanity:
	forge script -vvv script/VanityMining.s.sol --fork-url https://1rpc.io/holesky
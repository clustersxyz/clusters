# Deployment Instructions for New Chain
# Deploy placeholder logic contract at 0x19670000000A93f312163Cec8C4612Ae7a6783b4 from 0x6Ed7D526b020780f694f3c10Dfb25E1b134D3215 with cast-deploy-vanityimpl-placeholder
# Deploy vanity proxy at 0x00000000000E1A99dDDd5610111884278BDBda1D from 0x6Ed7D526b020780f694f3c10Dfb25E1b134D3215 with deployVanityProxy()
# Deploy singlesig (if necessary) at 0x000000dE1E80ea5a234FB5488fee2584251BC7e8 with cast-deploy-singlesig from delegate-registry repo
# Call upgradeInitiator() with correct lzProdEndpoint address
# Call configureHub() on ethereum mainnet
# Test hookup with doInitiate() simulate forge call
# If this fails, call setOriginSendConfig() in SetDVNConfig.s.sol, then call setDestReceiveConfig()

script-local:
	forge script script/Clusters.s.sol

sim-deploy-testnet:
	forge script -vvvvv script/Testnet.s.sol --sig "run()"

deploy-testnet:
	forge script -vvv script/Testnet.s.sol --sig "run()" --broadcast

call-beta-hub:
	# For live deployment, add --broadcast --verify --delay 30 --etherscan-api-key ${ETHERSCAN_API_KEY}
	forge script -vvvvv script/DeployBeta.s.sol --sig "configureHub()" --fork-url ${ETHEREUM_RPC_URL} --private-key ${PK}
	# forge script -vvv script/DeployBeta.s.sol --sig "upgradeInitiator()" --fork-url ${PLUME_RPC_URL} --private-key ${PK}

call-batch-refund:
	forge script -vvv script/BatchInteraction.s.sol --sig "run()"

call-beta-initiator:
	# --gas-estimate-multiplier 1000
	forge script -vvv script/DeployBeta.s.sol --sig "doInitiate()" --fork-url ${RPC_URL} --private-key ${PK} -vvv
	# forge script -vvv script/SetDVNConfig.s.sol --sig "setDestReceiveConfig()" -vvv

verify:
	forge verify-contract 0xa8a8157F4ed368F9d15468670253aC00c5661Ba9 src/beta/ClustersInitiatorBeta.sol:ClustersInitiatorBeta --chain 167000  --etherscan-api-key ${ETHERSCAN_API_KEY} --retries 5 --delay 30 --watch

cast-deploy-vanityimpl-placeholder:
	cast send --rpc-url ${RPC_URL} --private-key ${PK} 0x0000000000ffe8b47b3e2130213b802212439497 0x64e03087000000000000000000000000000000000000000097e5b90d2f1f6025db407f4d000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000002db60a06040523060805234801561001457600080fd5b506080516102a561003660003960008181606c015261015201526102a56000f3fe6080604052600436106100295760003560e01c80634f1ef2861461002e57806352d1902d14610043575b600080fd5b61004161003c3660046101fa565b61006a565b005b34801561004f57600080fd5b5061005861014e565b60405190815260200160405180910390f35b7f00000000000000000000000000000000000000000000000000000000000000003081036100a057639f03a0266000526004601cfd5b6100a9846101ad565b8360601b60601c93506352d1902d6001527f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc80602060016004601d895afa51146100fb576355299b496001526004601dfd5b847fbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b600038a2849055811561014857604051828482376000388483885af4610146573d6000823e3d81fd5b505b50505050565b60007f000000000000000000000000000000000000000000000000000000000000000030811461018657639f03a0266000526004601cfd5b7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc91505090565b70de1e80ea5a234fb5488fee2584251bc7e833146101f7576040517f82b4290000000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b50565b60008060006040848603121561020f57600080fd5b833573ffffffffffffffffffffffffffffffffffffffff8116811461023357600080fd5b9250602084013567ffffffffffffffff8082111561025057600080fd5b818601915086601f83011261026457600080fd5b81358181111561027357600080fd5b87602082850101111561028557600080fd5b602083019450809350505050925092509256fea164736f6c6343000817000a0000000000
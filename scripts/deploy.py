import IPython
import warnings
from eth_utils import keccak
from ape import project, networks, accounts, Contract

rocketStorageAddresses = dict(
        mainnet='0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46',
        holesky='0x594Fb75D3dc2DFa0150Ad03F99F97817747dd4E1')

def main():
    network_name = networks.network.name
    provider_uri = networks.active_provider.uri
    if network_name != 'holesky-fork':
        raise f'Only holesky-fork is currently supported, not {network_name}'
    deployer = accounts.test_accounts[0]
    deployer.deploy(project.rocketlend, rocketStorageAddresses['holesky'])
    print(f'RPC available at {provider_uri}')
    rocketStorage = Contract(rocketStorageAddresses['holesky'])
    rocketVault = accounts[rocketStorage.getAddress(keccak('contract.addressrocketVault'.encode()))]
    RPLToken = Contract(rocketStorage.getAddress(keccak('contract.addressrocketTokenRPL'.encode())))
    amountRPL = 1000
    amount = amountRPL * 10 ** RPLToken.decimals()
    RPLToken.transfer(deployer, amount, sender=rocketVault)
    print(f'Grabbed {amountRPL} RPL for {deployer.address} with private key {deployer.private_key}')
    warnings.filterwarnings('ignore')
    IPython.embed()

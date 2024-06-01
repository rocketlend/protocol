import IPython
import warnings
from ape import project, networks, accounts

rocketStorageAddresses = dict(
        mainnet='0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46',
        holesky='0x594Fb75D3dc2DFa0150Ad03F99F97817747dd4E1')

def main():
    network_name = networks.network.name
    provider_uri = networks.active_provider.uri
    if network_name != 'holesky-fork':
        raise f'Only holesky-fork is currently supported, not {network_name}'
    accounts.test_accounts[0].deploy(project.Rocketlend, rocketStorageAddresses['holesky'])
    print(f'RPC available at {provider_uri}')
    warnings.filterwarnings('ignore')
    IPython.embed()

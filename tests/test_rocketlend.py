import pytest
from ape import Contract, reverts

rocketStorageAddresses = dict(
        mainnet='0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46',
        holesky='0x594Fb75D3dc2DFa0150Ad03F99F97817747dd4E1')

@pytest.fixture(scope='session')
def rocketStorage(chain):
    return Contract(rocketStorageAddresses[chain.provider.network.name.removesuffix('-fork')])

@pytest.fixture(scope='session')
def RPLToken(rocketStorage):
    return Contract(rocketStorage.getAddress(keccak('contract.addressrocketTokenRPL'.encode())))

@pytest.fixture(scope='session')
def deployer(accounts):
    return accounts[5]

@pytest.fixture(scope='session')
def rocketlend(project, rocketStorage, deployer):
    return project.Rocketlend.deploy(rocketStorage.address, sender=deployer)

def test_deploy(rocketlend):
    pass

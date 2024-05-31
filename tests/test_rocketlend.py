import pytest
from eth_utils import keccak
from ape import reverts

rocketStorageAddresses = dict(
        mainnet='0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46',
        holesky='0x594Fb75D3dc2DFa0150Ad03F99F97817747dd4E1')

@pytest.fixture(scope='session')
def rocketStorage(chain, Contract):
    return Contract(rocketStorageAddresses[chain.provider.network.name.removesuffix('-fork')])

@pytest.fixture(scope='session')
def RPLToken(rocketStorage, Contract):
    return Contract(rocketStorage.getAddress(keccak('contract.addressrocketTokenRPL'.encode())))

@pytest.fixture(scope='session')
def deployer(accounts):
    return accounts[5]

@pytest.fixture(scope='session')
def admin(accounts):
    return accounts[4]

@pytest.fixture(scope='session')
def other(accounts):
    return accounts[3]

@pytest.fixture()
def rocketlend(project, rocketStorage, deployer):
    return deployer.deploy(project.Rocketlend, rocketStorage)

def test_RPL_token_address(rocketlend, RPLToken):
    assert rocketlend.RPL() == RPLToken.address

def test_rocketstorage_address(rocketlend, rocketStorage):
    assert rocketlend.rocketStorage() == rocketStorage.address

def test_admin_initial_address(rocketlend, deployer):
    assert rocketlend.protocol().address == deployer

def test_other_change_address(rocketlend, other):
    with reverts("auth"):
        rocketlend.changeAdminAddress(other, True, sender=other)
    with reverts("auth"):
        rocketlend.changeAdminAddress(other, False, sender=other)

@pytest.fixture()
def rocketlendAdmin(rocketlend, deployer, admin):
    rocketlend.changeAdminAddress(admin, False, sender=deployer)
    rocketlend.confirmChangeAdminAddress(sender=admin)
    return rocketlend

def test_admin_change_address(rocketlendAdmin, admin):
    assert rocketlendAdmin.protocol().address == admin

def test_admin_change_address_event(rocketlend, deployer, admin):
    r1 = rocketlend.changeAdminAddress(admin, False, sender=deployer)
    assert len(rocketlend.UpdateAdmin.from_receipt(r1)) == 0
    r2 = rocketlend.confirmChangeAdminAddress(sender=admin)
    logs = rocketlend.UpdateAdmin.from_receipt(r2)
    assert len(logs) == 1
    assert logs[0]['old'] == deployer
    assert logs[0]['new'] == admin

def test_admin_change_address_noconfirm(rocketlend, deployer, admin):
    rocketlend.changeAdminAddress(admin, True, sender=deployer)
    assert rocketlend.protocol().address == admin

def test_other_withdraw_fees(rocketlendAdmin, other):
    with reverts("auth"):
        rocketlendAdmin.withdrawFees(sender=other)

def test_admin_withdraw_no_fees(rocketlendAdmin, admin, RPLToken):
    receipt = rocketlendAdmin.withdrawFees(sender=admin)
    transfers = RPLToken.Transfer.from_receipt(receipt)
    assert len(transfers) == 1
    assert transfers[0]['from'] == rocketlendAdmin
    assert transfers[0]['to'] == admin
    assert transfers[0]['value'] == 0

def test_create_pool_unregistered(rocketlendAdmin, other):
    with reverts('auth'):
        rocketlendAdmin.createPool(dict(lender=0, interestRate=0, endTime=0, protocolFee=0), 0, 0, sender=other)

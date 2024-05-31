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
def rocketNodeManager(rocketStorage, Contract):
    return Contract(rocketStorage.getAddress(keccak('contract.addressrocketNodeManager'.encode())))

@pytest.fixture(scope='session')
def deployer(accounts):
    return accounts[5]

@pytest.fixture(scope='session')
def admin(accounts):
    return accounts[4]

@pytest.fixture(scope='session')
def other(accounts):
    return accounts[3]

@pytest.fixture(scope='session')
def lender1(accounts):
    return accounts[1]

@pytest.fixture(scope='session')
def lender2(accounts):
    return accounts[2]

@pytest.fixture(scope='session')
def borrower1(rocketNodeManager, accounts):
    nodeAddress = rocketNodeManager.getNodeAt(42)
    return accounts[nodeAddress]

@pytest.fixture(scope='session')
def borrower2(rocketNodeManager, accounts):
    nodeAddress = rocketNodeManager.getNodeAt(69)
    return accounts[nodeAddress]

@pytest.fixture(scope='session')
def borrowerLender(rocketNodeManager, accounts):
    nodeAddress = rocketNodeManager.getNodeAt(420)
    return accounts[nodeAddress]

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

def test_register_lender1(rocketlendAdmin, lender1):
    nextId = rocketlendAdmin.nextLenderId()
    assert nextId == 0
    receipt = rocketlendAdmin.registerLender(sender=lender1)
    assert receipt.return_value == nextId
    logs = rocketlendAdmin.RegisterLender.from_receipt(receipt)
    assert len(logs) == 1
    assert logs[0]['id'] == nextId
    assert logs[0]['address'] == lender1

def test_change_borrower_other(rocketlendAdmin, borrower1, other):
    with reverts('auth'):
        rocketlendAdmin.changeBorrowerAddress(borrower1, other, True, sender=other)

@pytest.fixture()
def rocketlendReg1(rocketlendAdmin, lender1):
    rocketlendAdmin.registerLender(sender=lender1)
    return rocketlendAdmin

def test_create_expired_pool(rocketlendReg1, lender1):
    params = dict(lender=0, interestRate=0, endTime=0, protocolFee=0)
    receipt = rocketlendReg1.createPool(params, 0, 0, sender=lender1)
    logs = rocketlendReg1.CreatePool.from_receipt(receipt)
    assert len(logs) == 1
    assert logs[0]['params'] == list(params.values())

def test_create_pool_wrong_fee(rocketlendReg1, lender1):
    with reverts('fee'):
        params = dict(lender=0, interestRate=0, endTime=0, protocolFee=1)
        rocketlendReg1.createPool(params, 0, 0, sender=lender1)

@pytest.fixture()
def rocketlendReg2(rocketlendReg1, lender2):
    rocketlendReg1.registerLender(sender=lender2)
    return rocketlendReg1

@pytest.fixture()
def rocketlendbl(rocketlendReg2, borrowerLender):
    rocketlendReg2.registerLender(sender=borrowerLender)
    return rocketlendReg2

def test_set_fee_other(rocketlendbl, other):
    with reverts('auth'):
        rocketlendbl.setFeeNumerator(100, sender=other)

def test_set_fee_too_high(rocketlendbl, admin):
    with reverts('max'):
        rocketlendbl.setFeeNumerator(300000, sender=admin)

@pytest.fixture()
def rocketlendf(rocketlendbl, admin):
    rocketlendbl.setFeeNumerator(10000, sender=admin)
    return rocketlendbl

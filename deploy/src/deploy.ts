import { readFileSync } from 'fs';
import { Contract, ContractFactory, ContractUtils, Provider, Wallet, WalletUnlocked } from 'fuels';

import { HyperlaneMailboxAbi__factory } from '../types/factories/HyperlaneMailboxAbi__factory';

// First default account from running fuel-client locally:
//   Address: 0x6b63804cfbf9856e68e5b6e7aef238dc8311ec55bec04df774003a2c96e0418e
//   Balance: 10000000
const PRIVATE_KEY =
  '0xde97d8624a438121b86a1956544bd72ed68cd69f2c99555b08b1e8c51ffd511c';

// Rather than generating a new random contract ID each time, we can use a consistent salt
// to have a deterministic ID as long as the bytecode of the contract stays the same.
// See here to understand how contract IDs are generated:
// https://fuellabs.github.io/fuel-specs/master/protocol/id/contract.html
const CONTRACT_SALT =
  '0x0000000000000000000000000000000000000000000000000000000000000000';

async function main() {
  const provider = new Provider('http://127.0.0.1:4000/graphql');
  const wallet = Wallet.fromPrivateKey(PRIVATE_KEY, provider);

  const mailbox = await deployOrGetMailbox(wallet);

  // const bytecode = readFileSync(
  //   '../contracts/hyperlane-mailbox/out/debug/hyperlane-mailbox.bin',
  // );

  // const factory = new ContractFactory(
  //   bytecode,
  //   HyperlaneMailboxAbi__factory.abi,
  //   wallet,
  // );

  // const mailboxAddress = ContractUtils.getContractId(
  //   bytecode,
  //   CONTRACT_SALT,
  //   ContractUtils.getContractStorageRoot([]),
  // );

  // console.log('Expected mailboxAddress', mailboxAddress);

  // const mailbox = await factory.deployContract({
  //   salt: CONTRACT_SALT,
  // });

  console.log('Deployed contracts:');
  console.log({
    mailbox: mailbox.id.toHexString(),
  });

  try{
    const dispatchTx = await mailbox.functions.dispatch(
      420,
      '0x6900000000000000000000000000000000000000000000000000000000000069',
      [1,2,3,5,6]
    ).txParams({
      gasPrice: 0,
    });

    const txRequest = await dispatchTx.getTransactionRequest();
    const txResponse = await mailbox.wallet!.sendTransaction(txRequest);
    const txResult = await txResponse.wait();
    console.log('Dispatched', txResult);
  } catch (e) {
    console.log('err', e)
  }

  console.log('hmm?');
  console.log('Current latest checkpoint:', (await mailbox.functions.latest_checkpoint().simulate()).value);
}

async function deployOrGetMailbox(wallet: WalletUnlocked): Promise<Contract> {
  const bytecode = readFileSync(
    '../contracts/hyperlane-mailbox/out/debug/hyperlane-mailbox.bin',
  );

  const factory = new ContractFactory(
    bytecode,
    HyperlaneMailboxAbi__factory.abi,
    wallet,
  );

  const expectedMailboxContractId = ContractUtils.getContractId(
    bytecode,
    CONTRACT_SALT,
    ContractUtils.getContractStorageRoot([]),
  );

  const maybeDeployedContract = await wallet.provider.getContract(expectedMailboxContractId);

  console.log('Expected expectedMailboxContractId', expectedMailboxContractId, maybeDeployedContract);

  // If the contract's already been deployed, just get the existing one without deploying
  if (maybeDeployedContract) {
    return new Contract(
      expectedMailboxContractId,
      HyperlaneMailboxAbi__factory.abi,
      wallet,
    );
  }

  return factory.deployContract({
    salt: CONTRACT_SALT,
  });
}

main();

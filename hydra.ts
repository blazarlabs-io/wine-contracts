// Hydra Operations //

// run :
// deno run --allow-net --allow-read --allow-write --allow-env --allow-run hydra.ts

import {
  Data,
  SpendingValidator,
  toUnit,
  Constr,
  fromText,
  MintingPolicy,
  Blockfrost, Lucid, 
} from "https://deno.land/x/lucid@0.10.7/mod.ts";
import { load } from "https://deno.land/std@0.224.0/dotenv/mod.ts";

const env = await load();

const BLOCKFROST = env[BLOCKFROST_API_KEY]
 
export const lucid = await Lucid.new(
  new Blockfrost(
    "https://cardano-preview.blockfrost.io/api/v0",
    BLOCKFROST,
  ),
  "Preview",
);

lucid.selectWalletFromPrivateKey(await Deno.readTextFile("owner.sk"));

const ownerPKH = lucid.utils.getAddressDetails(await Deno.readTextFile("owner.addr"))
.paymentCredential.hash;

const mint = await readMintValidator()
const mintCS = lucid.utils.mintingPolicyToId(mint)
const validator = await readLockValidator()

async function readMintValidator(): Promise<MintingPolicy> {
  const validator = JSON.parse(await Deno.readTextFile("plutus.json")).validators[2];
  return {
    type: "PlutusV2",
    script: validator.compiledCode
  };
}

async function readLockValidator(): Promise<SpendingValidator> {
  const validator = JSON.parse(await Deno.readTextFile("plutus.json")).validators[1];
  return {
    type: "PlutusV2",
    script: validator.compiledCode
  };
}

const ownerAddress = await Deno.readTextFile("owner.addr");

const validatorAddress = lucid.utils.validatorToAddress(validator) 
const lockHash = lucid.utils.getAddressDetails(validatorAddress).paymentCredential.hash

const tokenName = fromText("BlazarWine01")
const trackingToken = toUnit(mintCS, tokenName)

const updateRedeemer1 = Data.to(new Constr(0, [BigInt(1), fromText("ipfs://QmZQcJaBTGu1Czz3HpS81fAcWULwwRkbxNFE1fPWdiVYim")]))
const updateRedeemer2 = Data.to(new Constr(0, [BigInt(1), fromText("ipfs://QmbXR7YsGw4E4HaVXhTfoFHY8L8Ud7U96qo82pbGMHfuze")]))

const lDatum1 = Data.to(
  new Constr(0, [
    new Constr(0, [
      fromText("Rioja"),
      fromText("image"),
      fromText("ipfs://QmbXR7YsGw4E4HaVXhTfoFHY8L8Ud7U96qo82pbGMHfuze"),
      fromText("ipfs://QmbXR7YsGw4E4HaVXhTfoFHY8L8Ud7U96qo82pbGMHfuze")
    ])
  ]),
  new Constr(1, [BigInt(0)])
)

const lDatum2 = Data.to(
  new Constr(0, [
    new Constr(0, [
      fromText("Rioja"),
      fromText("image"),
      fromText("ipfs://QmZQcJaBTGu1Czz3HpS81fAcWULwwRkbxNFE1fPWdiVYim"),
      fromText("ipfs://QmZQcJaBTGu1Czz3HpS81fAcWULwwRkbxNFE1fPWdiVYim")
    ])
  ]),
  new Constr(1, [BigInt(1)])
)

// Set Up && Initialise //
const socket = new WebSocket("ws://127.0.0.1:4001")

async function initHead() {
  const message = JSON.stringify({
    "tag": "Init"
  })

  const response = socket.send(message)

  return response
}

async function commitToHead() {
  const userUtxos = await lucid.utxosAtWithUnit(ownerAddress, trackingToken)

  const response = await fetch('http://127.0.0.1:4001/commit', {
    method: 'POST',
    body: JSON.stringify(userUtxos),
  });

  const commitTx = await response.json();

  const txSigned = await commitTx.sign().complete();

  return txSigned.submit()
}

async function payToSelfWithData() {
  const getUtxos = await fetch(`http://127.0.0.1:4001/snapshot/utxo`, {
    method: 'GET',
  })

  const utxos = await getUtxos.json()

  const tx = await lucid 
    .newTx()
    .collectFrom(utxos)
    .payToAddressWithData(ownerAddress, { inline: lDatum1 }, { lovelace: 100n, [trackingToken]: 1n})
    .complete()

  const txSigned = await tx.sign().complete()

  const submitToHead = await fetch(`http://127.0.0.1:4001/cardano-transaction`, {
    method: 'POST',
    body: JSON.stringify(txSigned)
  })

  const response = await submitToHead.json()

  return response
}

async function payToContractWithData() {
  const utxoRes = await fetch(`http://127.0.0.1:4001/snapshot/utxo`, {
    method: 'GET',
  })

  const utxos = await utxoRes.json()

  const ownerUtxos = utxos.filter((utxo) => utxo.address === ownerAddress)

  const tx = await lucid
    .newTx()
    .collectFrom(ownerUtxos)
    .payToContract(
      validatorAddress,
      {
        inline: lDatum1
      },
      {
        [trackingToken]: 1
      }
    )
    .complete()

  const txSigned = await tx.sign().complete()

  const submitToHead = await fetch(`/cardano-transaction`, {
    method: 'POST',
    body: JSON.stringify(txSigned)
  })

  const response = await submitToHead.json()

  return response
}

async function updateTokenWithData() {
  const utxoRes = await fetch(`/snapshot/utxo`, {
    method: 'GET',
  })

  const utxos = await utxoRes.json()

  const ownerUtxos = utxos.filter((utxo) => utxo.address === ownerAddress)
  const contractUtxos = utxos.filter((utxo) => utxo.address === validatorAddress)

  const tx = await lucid
    .newTx()
    .collectFrom(ownerUtxos)
    .collectFrom(contractUtxos[0], updateRedeemer2)
    .attachSpendingValidator(validator)
    .payToContract(
      validatorAddress,
      {
        inline: lDatum2
      },
      {
        [trackingToken]: 1
      }
    )
    .complete()

  const txSigned = await tx.sign().complete()

  const submitToHead = await fetch(`/cardano-transaction`, {
    method: 'POST',
    body: JSON.stringify(txSigned)
  })

  const response = await submitToHead.json()

  return response
}

async function closeHead() {
  const message = JSON.stringify({
    "tag": "Close"
  })

  const response = socket.send(message)

  return response
}

//              //
// Transactions //
//              //

const initHeadTx = await initHead()

console.log(`Initialising Hydra Head!
    Message: 
    
    ${initHeadTx}
`)

const commitHeadTx = await commitToHead()

console.log(`Committed To Hydra Head!
    Message: 
    
    ${commitHeadTx}
`)

// const payToSelfTx = await payToSelfWithData()

// console.log(`Paid Token To Self!
//     Message: 
    
//     ${payToSelfTx}
// `)

// const payToContractTx = await payToContractWithData()

// console.log(`Deposited Token To Contract!
//     Message: 
    
//     ${payToContractTx}
// `)

// const updateTokenTx = await updateTokenWithData()

// console.log(`Updated Token In Contract!
//     Message: 
    
//     ${updateTokenTx}
// `)

// const closeHeadTx = await closeHead()

// console.log(`Closed Hydra Head!
//     Message: 
    
//     ${closeHeadTx}
// `)

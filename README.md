# wine

This Repo is for Supply Chain Tracking

```
WARNING
```

Testing on the testnet has associated costs like chain bloat and transaction fees, it is 
recommended NOT to submit transactions to the testnet until the final stages of testing, 
instead, output some dummy data or return some json object to verify function calls are 
being made.

*But Its The Testnet!?*

Yes it is, but we can still encouter issues like duplicate tokens if we arent careful, 
and that can mess with the expected results during testing.

## Integration To Backend

The transaction building functions are written in lucid in `wine.ts`

`wine.ts` currently uses Deno, to access the npm package for lucid, you need 
`lucid-cardano`


```sh
npm install lucid-cardano
```

you will also need a Blockfrost API key, you can get a free one on their website which 
will be good enough for now.

insert a key for the `preview` testnet at:

```
const BLOCKFROST = <YourApiKey>
```

We need to call these functions with some data (like new IPFS) to submit the transaction 
with an infrastructure wallet.

We output the txHash so we can record changes in a database.

---

## Infrastructure Wallet

To sign and submit transactions we wiil need an infrastructure wallet which will allow 
the backend to make token updates automatically, I have a script to generate a wallet 
`generate-credentials.ts` which will output a cli wallet - address and signing key - 
which you can use with the transaction code ( it is currently set up for my own testnet 
wallet ).

It will create an `owner.addr` and `owner.sk` file which will be needed for `wine.ts` 
like so:

```
lucid.selectWalletFromPrivateKey(await Deno.readTextFile("./owner.sk"));
```

this will initialise lucid with the infrastructure wallet as the one interacting, it 
will pay the fees, it will sign the transactions.

## Building

For the contracts:

```sh
aiken build
```

## Testing

To run all validator tests, simply do:

```sh
aiken check
```

---

## TODO

I need to optimise these contracts to increase throughput (so we can update multiple 
tokens in a single transaction)

and I need to do some general contract optimisation when we have a more complete version 
of the processes needed, and any that may be missing.

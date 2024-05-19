use aiken/bytearray
use aiken/dict
use aiken/hash.{Blake2b_224, Hash}
use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Mint, NoDatum, Output, OutputReference, ScriptContext,
  Spend, Transaction, TransactionId, find_input, find_script_outputs,
  placeholder,
}
use aiken/transaction/credential.{ScriptCredential, VerificationKey}
use aiken/transaction/value.{PolicyId, Value}
use wine/tools as t

//                      //
// Token Minting Policy //
//                      //

type MintAction {
  a: Int,
  b: Int,
  tn: ByteArray,
}

type TokenDatum {
  metadata: TokenMetadata,
  version: Int,
}

type TokenMetadata {
  name: ByteArray,
  mediaType: ByteArray,
  src: ByteArray,
  data: ByteArray,
}

validator(owner: VerificationKeyHash) {
  fn mint(r: MintAction, c: ScriptContext) -> Bool {
    let ScriptContext { transaction, purpose } = c
    expect Mint(policy_id) = purpose

    let Transaction { mint, outputs, .. } = transaction

    expect [(ref_asset_name, ref_amount), (frac_asset_name, frac_amount)] =
      mint
        |> value.from_minted_value
        |> value.tokens(policy_id)
        |> dict.to_list()

    expect tx_signed_by(transaction, owner)
    when r.a is {
      1 -> {
        expect Some(refOut) =
          list.head(
            list.filter(
              outputs,
              fn(output) {
                value.quantity_of(output.value, policy_id, ref_asset_name) == 1
              },
            ),
          )
        expect InlineDatum(datum) = refOut.datum
        expect _datum: TokenDatum = datum
        expect Some(fracOut) =
          list.head(
            list.filter(
              outputs,
              fn(output) {
                value.quantity_of(output.value, policy_id, frac_asset_name) == r.b
              },
            ),
          )
        expect InlineDatum(datum) = fracOut.datum
        expect _datum: DisDatum = datum
        let token_name_list = fraction_token_prefix(r.tn)
        let ref_tn_check =
          compare_token_names(ref_asset_name, list.at(token_name_list, 0))
        let frac_tn_check =
          compare_token_names(frac_asset_name, list.at(token_name_list, 1))
        ref_amount == 1 && frac_amount == r.b && ref_tn_check && frac_tn_check
      }
      _ -> {
        let token_name_list = fraction_token_prefix(r.tn)
        let ref_tn_check =
          compare_token_names(ref_asset_name, list.at(token_name_list, 0))
        let frac_tn_check =
          compare_token_names(frac_asset_name, list.at(token_name_list, 1))

        ref_amount == -1 && frac_amount == -r.b && ref_tn_check && frac_tn_check
      }
    }
  }
}

//                             //
// Ref Token Locking Validator //
//                             //

type LockAction {
  a: Int,
  b: ByteArray,
}

// New IPFS Src

validator(owner: VerificationKeyHash, cs: value.PolicyId) {
  fn lock(d: TokenDatum, r: LockAction, c: ScriptContext) -> Bool {
    expect Spend(ownRef) = c.purpose
    when r.a is {
      1 -> {
        let scriptHash = get_own_script_hash(ownRef, c.transaction.inputs)
        let out = get_own_singleton_output(scriptHash, c.transaction.outputs)
        expect InlineDatum(datum) = out.datum
        expect outD: TokenDatum = datum
        contains_single_token_of(out.value, cs) && tx_signed_by(
          c.transaction,
          owner,
        ) && outD.version == d.version + 1 && outD.metadata.name == d.metadata.name && outD.metadata.src == d.metadata.src && outD.metadata.mediaType == d.metadata.mediaType
      }
      // tx signed by owner
      // output contains single token (policyID)
      _ -> tx_signed_by(c.transaction, owner)
    }
    // tx signed by owner
  }
}

//                        //
// Distribution Validator //
//                        //

type DisAction {
  a: Int,
  b: Int,
}

type DisDatum {
  a: Int,
}

validator(owner: VerificationKeyHash) {
  fn distro(d: DisDatum, r: DisAction, c: ScriptContext) -> Bool {
    expect Spend(ownRef) = c.purpose
    when r.a is {
      1 -> {
        let scriptHash = get_own_script_hash(ownRef, c.transaction.inputs)
        let out = get_own_singleton_output(scriptHash, c.transaction.outputs)
        expect InlineDatum(datum) = out.datum
        expect outD: DisDatum = datum
        expect Some(input) =
          c.transaction.inputs
            |> find_input(ownRef)
        let in = input.output

        has_one_singleton_asset_less(in.value, out.value) && outD == d
      }
      _ -> tx_signed_by(c.transaction, owner)
    }
  }
}

//                  //
// Helper Functions //
//                  //

// reference Prefix
const refPrefix = #"000643b0"

// fraction Prefix
const fracPrefix = #"001bc280"

// PKH 
type VerificationKeyHash =
  Hash<Blake2b_224, VerificationKey>

// AssetName 
fn make_token_names(tn) -> List<value.AssetName> {
  let tokenName: value.AssetName = tn
  let refTn = tokenName
  let fracTn = tokenName

  [refTn, fracTn]
}

fn fraction_token_prefix(tn) {
  let token_names = make_token_names(tn)
  let token_name_prefix =
    [refPrefix, fracPrefix]
  list.map2(token_name_prefix, token_names, fn(a, b) { bytearray.concat(a, b) })
}

fn compare_token_names(an: value.AssetName, tn: Option<ByteArray>) -> Bool {
  expect Some(tn) = tn
  an == tn
}

fn tx_signed_by(tx: Transaction, pkh: VerificationKeyHash) {
  list.has(tx.extra_signatories, pkh)
}

fn get_own_script_hash(o: OutputReference, i: List<Input>) -> ByteArray {
  expect Some(input) =
    i
      |> find_input(o)
  expect ScriptCredential(scriptHash) = input.output.address.payment_credential

  scriptHash
}

fn get_own_singleton_output(c: ByteArray, o: List<Output>) -> Output {
  let script_outputs =
    o
      |> find_script_outputs(c)

  expect list.length(script_outputs) == 1

  expect Some(output) = list.head(script_outputs)

  output
}

fn contains_single_token_of(v: Value, p: PolicyId) -> Bool {
  let token_count = dict.values(value.tokens(v, p))
  token_count == [1]
}

fn has_one_singleton_asset_less(in: Value, out: Value) -> Bool {
  expect Some(policy_id) =
    value.without_lovelace(in)
      |> value.policies()
      |> list.head()

  how_many_tokens(out, policy_id) == how_many_tokens(in, policy_id) - 1
}

fn how_many_tokens(v: Value, p: PolicyId) -> Int {
  expect Some(n) =
    value.tokens(v, p)
      |> dict.values()
      |> list.head()

  n
}

//       //
// Tests //
//       //

test make_token_names_pass() {
  let tn = "face"
  make_token_names(tn) == ["face", "face"]
}

test make_token_names_fail() fail {
  let tn = "face"
  make_token_names(tn) == ["face", "cafe"]
}

test fraction_token_prefix_pass() {
  let tn = #"face"
  fraction_token_prefix(tn) == [#"000643b0face", #"001bc280face"]
}

test fraction_token_prefix_fail() fail {
  let tn = #"dead"
  fraction_token_prefix(tn) == [#"000643b0face", #"001bc280face"]
}

test compare_token_names_pass() {
  let tn = Some(#"face")
  let asset = #"face"

  compare_token_names(asset, tn)
}

test compare_token_names_fail() fail {
  let tn = Some(#"face")
  let asset = #"cafe"

  compare_token_names(asset, tn)
}

test tx_signed_by_pass() {
  let sigs = t.test_signatories()
  let t =
    placeholder()
      |> fn(transaction) { Transaction { ..transaction, extra_signatories: sigs } }
  tx_signed_by(t, #"face")
}

test tx_signed_by_fail() fail {
  let sigs = t.test_signatories()
  let t =
    placeholder()
      |> fn(transaction) { Transaction { ..transaction, extra_signatories: sigs } }
  tx_signed_by(t, #"cafe")
}

test get_own_script_hash_pass() {
  let addr = t.test_script_address(#"face")
  let placeholder_utxo =
    OutputReference { transaction_id: TransactionId(""), output_index: 0 }

  let pinput =
    Input {
      output_reference: placeholder_utxo,
      output: t.test_output(addr, value.from_lovelace(5), NoDatum),
    }

  get_own_script_hash(placeholder_utxo, [pinput]) == #"face"
}

test get_own_script_hash_fail() fail {
  let addr = t.test_script_address(#"face")
  let placeholder_utxo =
    OutputReference { transaction_id: TransactionId(""), output_index: 0 }

  let pinput =
    Input {
      output_reference: placeholder_utxo,
      output: t.test_output(addr, value.from_lovelace(5), NoDatum),
    }

  get_own_script_hash(placeholder_utxo, [pinput]) == #"cafe"
}

test get_own_singleton_output_pass() {
  let c = #"face"

  let addr = t.test_script_address(#"face")

  let outs =
    [t.test_output(addr, value.from_lovelace(5), NoDatum)]

  get_own_singleton_output(c, outs) == t.test_output(
    addr,
    value.from_lovelace(5),
    NoDatum,
  )
}

test get_own_singleton_output_fail() fail {
  let c = #"dead"

  let addr = t.test_script_address(#"face")

  let outs =
    [t.test_output(addr, value.from_lovelace(5), NoDatum)]

  get_own_singleton_output(c, outs) == t.test_output(
    addr,
    value.from_lovelace(5),
    NoDatum,
  )
}

test contains_single_token_of_pass() {
  let p = #"beef"
  let tn = #"face"
  let value = value.from_asset(p, tn, 1)

  contains_single_token_of(value, p)
}

test contains_single_token_of_fail() fail {
  let p = #"beef"
  let f = #"dead"
  let tn = #"face"
  let value = value.from_asset(p, tn, 1)

  contains_single_token_of(value, f)
}

test has_one_singleton_asset_less_pass() {
  let p: value.PolicyId = #"dead"
  let t: value.AssetName = #"cafe"
  let in = value.from_asset(p, t, 2)
  let out = value.from_asset(p, t, 1)

  has_one_singleton_asset_less(in, out)
}

test has_one_singleton_asset_less_fail() fail {
  let p: value.PolicyId = #"dead"
  let t: value.AssetName = #"cafe"
  let in = value.from_asset(p, t, 2)
  let out = value.from_asset(p, t, 3)

  has_one_singleton_asset_less(in, out)
}

test how_many_tokens_pass() {
  let p: value.PolicyId = #"dead"
  let t: value.AssetName = #"cafe"
  let v = value.from_asset(p, t, 2)

  how_many_tokens(v, p) == 2
}

test how_many_tokens_fail() fail {
  let p: value.PolicyId = #"dead"
  let t: value.AssetName = #"cafe"
  let v = value.from_asset(p, t, 2)

  how_many_tokens(v, p) == 3
}

validator(owner: VerificationKeyHash) {
  fn aMint(r: MintAction, c: ScriptContext) -> Bool {
    True
  }
}

validator(owner: VerificationKeyHash, cs: value.PolicyId) {
  fn aLock(d: TokenDatum, r: LockAction, c: ScriptContext) -> Bool {
    True
  }
}

validator(owner: VerificationKeyHash) {
  fn aDistro(d: DisDatum, r: DisAction, c: ScriptContext) {
    True
  }
}

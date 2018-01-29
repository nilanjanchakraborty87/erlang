%%
%% @doc Implementation of RSA encryption functions.
%%
%% Warning: This module is not supposed to be used directly
%% since it requires a dedicated PRNG. Use {@link rsa} module instead
%% which is a process wrapper for {@link rsa_lib}.
%%
%% @reference N.Ferguson, B.Schneier, T. Kohno. <em>Cryptography Engineering</em>.
%% Chapter 12. RSA
%%
-module(rsa_lib).
-author("Andrey Paramonov").

-export([generate_rsa_key/1, generate_rsa_prime/1]).
-export([decrypt_random_key_with_rsa/2, encrypt_random_key_with_rsa/1]).
-export([msg_to_rsa_number/2, sign_with_rsa/2, verify_rsa_signature/3]).

-include_lib("stdlib/include/assert.hrl").

%% =============================================================================
%% Chapter 12.4.5. Generating RSA Keys
%% =============================================================================

%%
%% @doc Returns a random prime in the interval 2^{k-1}...2^k-1
%% subject to P mod 3 =/= 1 and P mod 5 =/= 1.
%%
%% @param K size of the desired prime, in number of bits.
%%
-spec generate_rsa_prime(K :: 1024..4096) -> pos_integer().

generate_rsa_prime(K) when 1024 =< K, K =< 4096 ->
  generate_rsa_prime(K, 100 * K).

generate_rsa_prime(K, R) when 0 < R ->
  N = maths:random(maths:pow(2, K - 1), maths:pow(2, K) - 1),
  generate_rsa_prime(K, R, N, N rem 3 =/= 1 andalso N rem 5 =/= 1 andalso primes:is_prime(N)).

generate_rsa_prime(_, _, N, true) -> N;
generate_rsa_prime(K, R, _, false) -> generate_rsa_prime(K, R - 1).

%%
%% @doc Returns a newly generated RSA private key.
%% The key is a tuple of the following integers:
%% P, Q - prime factors of the modulus,
%% N - modulus of about K bits,
%% D3 - signing exponent,
%% D5 - decryption exponent.
%%
%% Public exponents are fixed:
%% 3 - signature verification exponent,
%% 5 - encryption exponent.
%%
%% @param K size of the modulus, in number of bits.
%%
-spec generate_rsa_key(K :: 2048..8192) -> {P, Q, N, D3, D5} when
  P :: pos_integer(), Q :: pos_integer(), N :: pos_integer(), D3 :: pos_integer(), D5 :: pos_integer().

generate_rsa_key(K) when 2048 =< K, K =< 8192 ->
  P = generate_rsa_prime(K div 2),
  Q = generate_rsa_prime(K div 2),
  ?assertNotEqual(P, Q),
  T = maths:lcm(P - 1, Q - 1),
  D3 = maths:mod_inv(3, T),
  D5 = maths:mod_inv(5, T),
  {P, Q, P * Q, D3, D5}.

%% =============================================================================
%% Chapter 12.4.6. Encryption
%% =============================================================================

%%
%% @doc Returns a tuple {K, C} where K is a random 256-bit symmetric key,
%% and C is the RSA-encrypted key.
%%
%% @param PK RSA public key
%%
-spec encrypt_random_key_with_rsa(PK :: {N :: pos_integer(), E :: pos_integer()}) ->
  {K :: binary(), C :: non_neg_integer()}.

encrypt_random_key_with_rsa({N, E}) ->
  BitSize = maths:ilog2(N),
  R = maths:random(0, maths:pow(2, BitSize) - 1),
  K = crypto:hash(sha256, binary:encode_unsigned(R)),
  {K, maths:mod_exp(R, E, N)}.

%%
%% @doc Returns the 256-bit symmetric key K that was generated by
%% {@link encrypt_random_key_with_rsa/1}.
%%
%% @param SK RSA private key
%% @param C RSA-encrypted symmetric key
%%
-spec decrypt_random_key_with_rsa(
    SK :: {N :: pos_integer(), D :: pos_integer()},
    C :: non_neg_integer()) -> binary().

decrypt_random_key_with_rsa({N, D}, C) when 0 =< C, C < N ->
  crypto:hash(sha256, binary:encode_unsigned(maths:mod_exp(C, D, N))).

%% =============================================================================
%% Chapter 12.4.7. Signatures
%% =============================================================================

%%
%% @doc Returns a pseudo-random number modulo N used to create a signature.
%%
%% @see sign_with_rsa/2
%%
%% @param N Modulus of RSA public key.
%% @param M Message to be converted to a value modulo N.
%%
-spec msg_to_rsa_number(N :: pos_integer(), M :: binary()) -> pos_integer().

msg_to_rsa_number(N, M) ->
  K = size(binary:encode_unsigned(N)),
  bin:rand_seed(crypto:hash(sha256, M)),
  X = bin:rand_bytes(K),
  X rem N.

%%
%% @doc Signs the message with RSA private key.
%%
%% Instead of decrypting hash of the message, we seed PRNG with the hash
%% and decrypt the first random integer of the same size as modulus.
%%
%% @param SK RSA private key with E = 3.
%% @param M Message to be signed.
%%
%% @see msg_to_rsa_number/2
%%
-spec sign_with_rsa(SK :: {N :: pos_integer(), D :: pos_integer()}, M :: binary()) -> pos_integer().

sign_with_rsa({N, D}, M) when is_integer(M) ->
  sign_with_rsa({N, D}, binary:encode_unsigned(M));
sign_with_rsa({N, D}, M) when is_binary(M) ->
  S = msg_to_rsa_number(N, M),
  maths:mod_exp(S, D, N).

%%
%% @doc Verifies RSA signature of the message M.
%%
%% @param PK RSA public key with modulus N and exponent E = 3.
%% @param M Message that is supposed to be signed.
%% @param Sig Signature of the message.
%%
-spec verify_rsa_signature(PK :: {N :: pos_integer(), E :: pos_integer()},
    M :: binary(), Sig :: pos_integer()) -> ok.

verify_rsa_signature({N, E}, M, Sig) ->
  S = msg_to_rsa_number(N, M),
  S = maths:mod_exp(Sig, E, N),
  ok.


%% =============================================================================
%% Unit tests
%% =============================================================================

-include_lib("eunit/include/eunit.hrl").

-define(SK, {
  16#F01EC3CC06CEB98449CD10CEED03C3CC02D68DAB3D168C46C4102426BF012425246AD9F6E89561EF0C5ADDE586F9DE787CFF5669CEBC28199B51329B43319A227E2F0CBF5FFB608E13CEACC7B974A1CFBD55E08D4C4144D43C3B7B61FCED9CA013B9E1800CECBCC63A3215FFAACE395BB585C74F5DD94105E40ED8103D79431D,
  16#EBA58019CC067C29F20422540B1539472582F34BE52B365BA2DEC6243A3167F80874EEA8FECF3B9D8FA153068C393E45948A09776B63C7E217B83C8780B6655EAD5CEDC9DE3501C9EDCC2A18333C7BD6B70253042E63CF6BD0185F2A60D3BCB43A36F20124687FD02CF1FDE3EC109A80CA9EC64CFE6E9F354916B2ABD58DACA9,
  16#DD0779B81105E31373EF1BD75B5E5A1FFDB647317299300DBC5C01C64D5B3C1FBA39BC467648E7CC3DB3635964568DEE7CAF1C6E8676CB09D413278091A81200B2001F5409835C4799E190CE5E6FA51DBEFDF2E1DBC305E5457C3CF20EE4D13AF4456DD8B6D574B844B613E9F9158AEADC1B03C55375673A8DAE2DEA4D11A1307C6EE7E34904228F0A6D0C691F803275283819F380969C7AF7FC80C546A76279587FBBF4AC706D67465686CB868507D37F32DC3878251F754DBD2B4C8B1A53D24D29C12D2A111263E812FB6501329363DE2149150117716B489F61422C6F0F5F39BCB001B76235A2275F284A5AC846C845F09D73256D3A3775374B06261DCA25,
  16#24D69449582BA5D8935284A3E48FB9AFFF9E6132E86EDD579F64AAF66239DF5A9F099F6113B6D14CB4F33B3990B917A7BF7284BD166921D6F8ADDBEAC2F1585573000538AC408F61445042CD0FBD462F9FD4FDD04F4B2BA6363F5F7DAD2622DF28B63CF973CE3E1EB61E58A6FED8EC7C7A0480A0E33E3BDF179D07A70CD84587C571C5FF93B27CD0226F4EE106913390554FC42A0FB8CEF96D8243BF0CE8CE64B1EFFDE3762CA2A471B9B8FA933851D8E79C3F63DFAB87E999C89F5C4BDDB8B83044F670A7501D57511406162E15939F91A18395EBBDBA31DF61EBC8F7C79E57274CA4C016577ED74AB4836675FC3DD1F64CAD4E76DB8EFF61584AB7032E79BB,
  16#B0D2C7C67404B5A9298C1645E2B1E1B3315E9F5AC2142671637CCE383DE2967FC82E30385EA0B970315C4F7AB6ABA4BECA25B0586B923C07DCDC1F9A0E200E66F4CCE5DCD469169FAE4E0D71E5261DB16597F5817C9C04B76AC9CA5B3F1D742F29D124AD5F112A2D03C4DCBB2DAAD588B0159C9DDC5DEC2ED7BE8B21D7414DBEE6EEE99791BF23E70BAFE104EC52911B33187A637EAA47E0740ADEC83DF711E356198F77040973155515117F8F74BC11248796AC319DBF947BC2FCEE38F51040E7B16BB6564D59A31EC6839DAA012AFDEE3A779C6B8EB0EF636F9EF7D88AF808BCA316CD380A60D6336276B89CBAC25637D673123A8447FD067499D4DC12485
}).

encrypt_decrypt_key_test() ->
  {_P, _Q, N, _D3, D5} = ?SK,
  {K, C} = encrypt_random_key_with_rsa({N, 5}),
  ?assertEqual(K, decrypt_random_key_with_rsa({N, D5}, C)).

msg_to_rsa_number_test() ->
  {_P, _Q, N, _D3, _D5} = ?SK,
  M = <<1, 2, 3>>,
  S = 16#6B1756A121DF748A364E27186207BDCD28EAF66ACC9F41C6AE12B81BFEDC19D34BAA8C05FCE66EA7EBA0FE316F4DA4AB967C2881B34FC887993A89D9175D7CBAB798F8F70D1F7EA172A5D36E4C4F91F2D9175E7F0D3CF0FCFEC570C5A6DE6D5C2347C1363CDFBC98DCD8E0138BFBF60831F6B675B0103C12DF41BCDB2CD0391D6F9F76BFA8B2747BD02560A4ACFE607BBA9914D7812C171C2814318EFB1C136058F8C29639BEAF95373C06E7E18145CDDD6999491B70672E075A1169C9835B2A86B62DE71CD32154A1F0815B85FFA857706AEEFB379FB8429D70D67C11CEBD53B014A8C59D28AC640ECE569A2C031BE7F7737F0FD4FAEC56B1BAAEAED3A5D346,
  ?assertEqual(S, msg_to_rsa_number(N, M)).

sign_verify_test_() ->
  {_P, _Q, N, D3, _D5} = ?SK,
  M = <<1, 2, 3>>,
  Sig = 16#961C5B057698A05BAFA2BAF0BD2305C7F402F23C3ADFFF82890A3DC50503CE233F26C8A9068F48217C028010218DB1876DCA0772B8DB57F7D370A97B616CAD361C0BC01666E7C208C478DFF4CD4DD3866595E01C4041A5815D04DA8D50D418FAC0E8F45B48F9FF7EFDDAE41F4FE396B952DEA088381E11300D61669D37141452F23E8E55A1D0477B4692F3B0DD664F45479E9BED1E542FEF011A59356D78D6668E6F84910F609058032118D72A30E81F54B27A9346EC0E24082DCEC442AC8134C88A258DCD802D47F4AF8502FF611BB62BF30AFBA11841EF32B34B478E3AC5BE8D64308EBA5463E3E92730B65FB25C5175AC8B1C46E4D93C3C130CF2667A2350,
  [
    ?_assertEqual(Sig, sign_with_rsa({N, D3}, M)),
    ?_assertEqual(ok, verify_rsa_signature({N, 3}, M, Sig))
  ].

%% @see rsa:sign_verify_hides_prng_test/0
sign_verify_messing_with_prng_test() ->
  {_P, _Q, N, D3, _D5} = ?SK,
  M = <<1, 2, 3>>,
  Sig = sign_with_rsa({N, D3}, M),
  RandomNumber = rand:uniform(maths:pow(2, 256)),
  verify_rsa_signature({N, 3}, M, Sig),
  ?assertEqual(RandomNumber, rand:uniform(maths:pow(2, 256))). % sic!

signature_product_test() ->
  N = (P = 71) * (Q = 89),
  ?assertEqual(6319, N),

  T = maths:lcm(P - 1, Q - 1),
  ?assertEqual(3080, T),

  D = maths:mod_inv(3, T),
  ?assertEqual(1027, D),

  S1 = sign_with_rsa({N, D}, M1 = 5416),
  ?assertEqual(923, S1),

  S2 = sign_with_rsa({N, D}, M2 = 2397),
  ?assertEqual(2592, S2),

  S3 = sign_with_rsa({N, D}, M1 * M2 rem N),
  ?assertEqual(5086, S3), % not equal to
  ?assertEqual(3834, S1 * S2 rem N).

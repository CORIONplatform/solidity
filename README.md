
# CORION platform
Ethereum contract based multifunctional platform.

## Our contacts
Website:
https://www.corion.io

Email:
contact@corion.io

Bitcoin Talk:
https://bitcointalk.org/index.php?topic=1920823.0

Slack:
https://corionplatform.slack.com/shared_invite/MTg0MDIwNjM1NTIxLTE0OTUwMjE5MjEtNDcxYTdlZGUxYg

## Contract on the Ethereum Classic blockchain
Coming soon..

## Contracts deploy order
#### #1 moduleHandler without any construction parameter.
#### #2 exchange without any construction parameter.
#### #3 ico with the parameters:
1. Foundation ethereum address
2. Address which will change the exchange rate during ICO
3. Start exchange rate (This must be multiplied with 1e4)
4. ICO starting block (if 0 then start immediately)
5. Genesis addresses array
6. Genesis balances array
#### #4 tokenDB without any construction parameter.
#### #5 token with the parameters:
1. Boolean that is for replace or not? That means if this the first deploy this must be `false`.
2. moduleHandler address
3. tokenDB address
4. ico address
5. exchange (contract) address
6. Genesis addresses array
7. Genesis balances array
#### #6 ptokenDB (Premium token database) without any construction parameter.
#### #7 premium with parameters:
1. Boolean that is for replace or not? That means if this the first deploy this must be `false`
2. moduleHandler address
3. ptokenDB address
4. ico address
5. Genesis addresses array
6. Genesis balances array
#### #8 publisher with the parameters:
1. moduleHandler address
#### #9 provider with the parameters:
1. moduleHandler address
#### #10 schellingDB without any construction parameter.
#### #11 schelling with parameters:
1. moduleHandler address
2. schellingDB address
3. Boolean that is for replace or not? That means if this the first deploy this must be `false`
#### #12 call moduleHandler load function with the parameters:
1. foundation address
2. Boolean that is for replace or not? That means if this the first deploy this must be `false`
3. token address
4. premium address
5. publihser address
6. schelling address
7. provider address
#### #13 (OPTIONAL) Starting ICO with call the ico contract connectTokens function with the parameters:
1. token address
2. premium address

# Licence

See LICENCE

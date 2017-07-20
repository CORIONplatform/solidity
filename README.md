
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

## BUG BOUNTY
Corion Team is starting a bug bounty program for some of the contracts relevant for our token launch.
(It requirse programming skills and solidity language expertise.)

~~Minor bug fixes will be rewarded with 15 ETC~~

~~Major bugs, Critical vulnerabilities and fix 75 ETC!~~

~~The bounty program will be capped at 300 ETC if there were more bugs than that, we will split reward 50% ETC 50% Corion tokens.~~

**We raise the bug bounty reward!**

The BugBounty would be decreasing from 250 ETC to 150 ETC.

It looks like this:

Who find the 1st Critical Bug: 250 ETC

Who find the 2nd Critical Bug: 225 ETC

Who find the 3rd Critical Bug: 200 ETC

Who find the 4th Critical Bug: 175 ETC

Who find the 5th Critical Bug: 150 ETC

From the 6th Critical Bug: 150 ETC/bug

Critical mistake is a mistake that can't be fixed through module replacing.

For minor mistake we pay for you 15 ETC/bug.

Most of the rules on https://bounty.ethereum.org apply. For example: First come, first serve. Issues that have already been submitted by another user or are already known to the team are not eligible for bounty rewards.

### SCOPE
Being able to obtain more tokens then expected, 
Being able to obtain Corion from someone without their permission
Bugs that allow the owner to loose tokens in his posession, during the ICO perion or after
Bugs causing a transaction to be sent which is different what the user intend to do sending 100 instead of 10, etc.

SCOPE of contracts:
`Publisher`, `ModuleHandler`, `ICO`, `Premium`, `Token`, `TokenDB`, `PtokenDB`

The Bug Hunt will last 10 days, start on 11-07-17 till 21-07-17.

Submission to https://github.com/CORIONplatform/solidity/issues !

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
5. publisher address
6. schelling address
7. provider address
#### #13 (OPTIONAL) Starting ICO with call the ico contract connectTokens function with the parameters:
1. token address
2. premium address

# Licence

See LICENCE

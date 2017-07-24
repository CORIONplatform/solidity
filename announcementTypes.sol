pragma solidity ^0.4.11;

contract announcementTypes {

    enum announcementType {
        /*
            type of announcements
        */
        newModule,
        dropModule,
        replaceModule,
        replaceModuleHandler,
        question,
        transactionFeeRate,
        transactionFeeMin,
        transactionFeeMax,
        transactionFeeBurn,
        exchangeAddress, 
        providerPublicFunds,
        providerPrivateFunds,
        providerPrivateClientLimit,
        providerPublicMinRate,
        providerPublicMaxRate,
        providerPrivateMinRate,
        providerPrivateMaxRate,
        providerGasProtect,
        providerInterestMinFunds,
        providerRentRate,
        schellingRoundBlockDelay,
        schellingCheckRounds,
        schellingCheckAboves,
        schellingRate,
        publisherMinAnnouncementDelay,
        publisherOppositeRate
    }
}

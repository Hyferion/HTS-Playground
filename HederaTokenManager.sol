// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;


import {KeysLib} from './library/KeysLib.sol';
import {SafeCast} from './library/SafeCast.sol';
import {HederaTokenService} from './HederaTokenService.sol';
import {HederaResponseCodes} from './HederaResponseCodes.sol';
import {IERC20Metadata} from './IERC20Metadata.sol';
import {IERC20} from './IERC20.sol';
import './ExpiryHelper.sol';
import './KeyHelper.sol';
import "./IHederaTokenManager.sol";

contract HederaTokenManager is HederaTokenService, IHederaTokenManager, ExpiryHelper, KeyHelper
{
    address internal constant _PRECOMPILED_ADDRESS = address(0x167);
    address public tokenAddress;

    event ResponseCode(int responseCode);
    event MintedToken(int64 newTotalSupply, int64[] serialNumbers);

    constructor() {    }


    function createToken() external payable {
        IHederaTokenService.HederaToken memory token;
        token.name = "DCHF";
        token.symbol = "DCHF";
        token.treasury = address(this);

        token.expiry = createAutoRenewExpiry(address(this), 7000000);

        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](5);
        keys[0] = getSingleKey(KeyType.ADMIN, KeyType.PAUSE, KeyValueType.INHERIT_ACCOUNT_KEY, bytes(""));
        keys[1] = getSingleKey(KeyType.KYC, KeyValueType.INHERIT_ACCOUNT_KEY, bytes(""));
        keys[2] = getSingleKey(KeyType.FREEZE, KeyValueType.INHERIT_ACCOUNT_KEY, bytes(""));
        keys[3] = getSingleKey(KeyType.WIPE, KeyValueType.INHERIT_ACCOUNT_KEY, bytes(""));
        keys[4] = getSingleKey(KeyType.SUPPLY, KeyValueType.INHERIT_ACCOUNT_KEY, bytes(""));

        token.tokenKeys = keys;

        (int responseCode, address createdTokenAddress) =
        HederaTokenService.createFungibleToken(token, 0, 8);

        _checkResponse(responseCode);
        tokenAddress = createdTokenAddress;
    }

    function mintTokenPublic(address token, int64 amount) public
    returns (int responseCode, int64 newTotalSupply, int64[] memory serialNumbers)  {
        (responseCode, newTotalSupply, serialNumbers) = HederaTokenService.mintToken(token, amount,new bytes[](0));
        emit ResponseCode(responseCode);

        if (responseCode != HederaResponseCodes.SUCCESS) {
            revert();
        }

        emit MintedToken(newTotalSupply, serialNumbers);
    }

    function mint(
        address account,
        int64 amount
    )
    external
    returns (bool)
    {
        address currentTokenAddress = _getTokenAddress();

        uint256 balance = _balanceOf(address(this));

        (int64 responseCode, ,) = IHederaTokenService(_PRECOMPILED_ADDRESS)
            .mintToken(currentTokenAddress, amount, new bytes[](0));

        bool success = _checkResponse(responseCode);

        if (
            !((_balanceOf(address(this)) - balance) ==
            SafeCast.toUint256(amount))
        ) revert('The smart contract is not the treasury account');

        _transfer(account, amount);

        emit TokensMinted(msg.sender, currentTokenAddress, amount, account);

        return success;
    }

    function burn(
        int64 amount
    )
    external
    returns (bool)
    {
        address currentTokenAddress = _getTokenAddress();

        (int64 responseCode,) = IHederaTokenService(_PRECOMPILED_ADDRESS)
            .burnToken(currentTokenAddress, amount, new int64[](0));

        bool success = _checkResponse(responseCode);

        emit TokensBurned(msg.sender, currentTokenAddress, amount);

        return success;
    }

    function _getTokenAddress() internal view returns (address) {
        return tokenAddress;
    }

    /**
     * @dev Returns the name of the token
     *
     * @return string The the name of the token
     */
    function name() external view returns (string memory) {
        return IERC20Metadata(_getTokenAddress()).name();
    }

    /**
     * @dev Returns the symbol of the token
     *
     * @return string The the symbol of the token
     */
    function symbol() external view returns (string memory) {
        return IERC20Metadata(_getTokenAddress()).symbol();
    }

    /**
     * @dev Returns the number of decimals of the token
     *
     * @return uint8 The number of decimals of the token
     */
    function decimals() external view returns (uint8) {
        return _decimals();
    }

    /**
     * @dev Returns the total number of tokens that exits
     *
     * @return uint256 The total number of tokens that exists
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply();
    }

    /**
     * @dev Returns the number tokens that an account has
     *
     * @param account The address of the account to be consulted
     *
     * @return uint256 The number number tokens that an account has
     */
    function balanceOf(
        address account
    ) external view override(IHederaTokenManager) returns (uint256) {
        return _balanceOf(account);
    }


    /**
     * @dev Returns the number tokens that an account has
     *
     * @param account The address of the account to be consulted
     *
     * @return uint256 The number number tokens that an account has
     */
    function _balanceOf(
        address account
    ) internal view returns (uint256) {
        return IERC20(_getTokenAddress()).balanceOf(account);
    }

    /**
     * @dev Transfers an amount of tokens from and account to another account
     *
     * @param to The address the tokens are transferred to
     */
    function _transfer(
        address to,
        int64 amount
    )
    internal
    {
        if (to != address(this)) {
            address currentTokenAddress = _getTokenAddress();

            int64 responseCode = IHederaTokenService(_PRECOMPILED_ADDRESS)
                .transferToken(currentTokenAddress, address(this), to, amount);

            _checkResponse(responseCode);

            emit TokenTransfer(currentTokenAddress, address(this), to, amount);
        }
    }

    /**
     * @dev Is required because of an Hedera's bug, when keys are updated for a token, the memo gets removed.
     *
     *
     * @return string The memo of the token
     */
    function _getTokenInfo() private returns (string memory) {
        (
            int64 responseCode,
            IHederaTokenService.TokenInfo memory info
        ) = IHederaTokenService(_PRECOMPILED_ADDRESS).getTokenInfo(
            tokenAddress
        );

        _checkResponse(responseCode);

        return info.token.memo;
    }

        /**
     * @dev Returns the number of decimals of the token
     *
     */
    function _decimals() internal view returns (uint8) {
        return IERC20Metadata(tokenAddress).decimals();
    }

        /**
     * @dev Returns the total number of tokens that exits
     *
     */
    function _totalSupply() internal view returns (uint256) {
        return IERC20(tokenAddress).totalSupply();
    }

    /**
     * @dev Transforms the response from a HederaResponseCodes to a boolean
     *
     * @param responseCode The Hedera response code to transform
     */
    function _checkResponse(int responseCode) internal pure returns (bool) {
        if (responseCode != HederaResponseCodes.SUCCESS)
            revert ResponseCodeInvalid(responseCode);
        return true;
    }

        /**
     * @dev Transfers the remaining HBARs from msg.value back to the original sender
     *
     * @param originalSender address of the original sender
     */
    function _transferFundsBackToOriginalSender(
        address originalSender
    ) private {
        uint256 currentBalance = address(this).balance;
        if (currentBalance == 0) return;
        (bool s,) = originalSender.call{value: currentBalance}('');
        if (!s) revert RefundingError(currentBalance);
    }
}
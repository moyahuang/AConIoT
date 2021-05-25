// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.8.0;
pragma experimental ABIEncoderV2;
import "./0_Shared.sol";
import "./1_DMC.sol";
import "./2_PC.sol";

/*
    @title Access Control Contract
    @author Moya
    @function policy enforcement point
    @date 2021/02/16
*/

contract PEC{
    address public owner;
    DMC public dmc;
    PC public pc;

    event ReturnAccessResult(
        address indexed from,
        string message,
        uint256 time,
        string location
    );

    struct attribute{
        bool isValued;
        string value;
        uint8 id;
    }

    constructor(address _dmc, address _pc){
        owner=msg.sender;
        dmc=DMC(_dmc);
        pc=PC(_pc);
    }

    // ps格式：32221110 其中3为EA 2为OA 1为SA 0为正负标记位
    function accessControl(
        address _object, 
        string memory _action
    )public{
        address subject=msg.sender;
        bool policyCheck=false;
        bool safeCheck=false;
       
        Shared.Sign sign=Shared.Sign.Deny;

        sign=pc.getPolicyCheck(_action, subject, _object);
        policyCheck=sign==Shared.Sign.Allow;

         // 此处的7为环境属性的序号
        string memory env=dmc.getAttribute(subject, 7);
        if(Shared.stringCompare(env, "in")){
            safeCheck=true;
        }

        string memory result=policyCheck && safeCheck?"Access Authorized!":"Access Denied";
       
        emit ReturnAccessResult(msg.sender, result, block.timestamp, env);
    }

}

// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.8.0;
pragma experimental ABIEncoderV2;
import "./1_DMC.sol";
import "./0_Shared.sol";

/** 
    @title Device Attribute Contract
    @author Moya
    function policy management
    date 2021/02/16
**/
contract PC{
    address public owner;
    enum PolicyMode{DenyOverrides,AllowOverrides}

    DMC public dmc;

    PolicyMode public defaultMode; 

    uint256 public rSize;
    uint256 public wSize;
    uint256 public eSize;

    // 属性序号值对 operator为= > <
    struct Rule{
        uint8 id;
        string value;
        // string operator;
    }

    // 策略是属性集合，属性包括操作上下文、主体属性、客体属性、操作
    struct Policy{
        uint256 id;
        Shared.Sign sign;
        byte ps; // prefix sign
        Rule[] rules;
        bool isValued;
        // mapping(string =>Rule[]) rules;
    }

    // struct Attribute{
    //     uint8 id;
    //     string value;
    //     bool isValued;
    // }
    // policies[action][id] id由0开始 action分三类r w x
    mapping(string => mapping(uint256 => Policy)) policies;

    constructor(address _dmc){
        owner=msg.sender;
        defaultMode=PolicyMode.AllowOverrides; //默认模式为allowoverrides
        dmc=DMC(_dmc);

        rSize=0;
        wSize=0;
        eSize=0;
    }

    function toggleMode() public {
        defaultMode==PolicyMode.AllowOverrides?
            defaultMode=PolicyMode.DenyOverrides:
            defaultMode=PolicyMode.AllowOverrides;
    }
   
   function addPolicy(
        string memory _action,
        Shared.Sign _sign,
        byte _ps,
        Rule[] memory _rules
    )public returns(uint256){
        require(msg.sender==owner, "Error: Only the SuperManager can add a policy");
        uint256 pointer;
        if(Shared.stringCompare(_action,'r')){
            pointer=rSize;
            rSize++;
        }else if(Shared.stringCompare(_action, 'w')){
            pointer=wSize;
            wSize++;
        }else if(Shared.stringCompare(_action, 'e')){ 
            pointer=eSize;
            eSize++;
        }
        
        policies[_action][pointer].id=pointer;
        policies[_action][pointer].sign=_sign;
        policies[_action][pointer].ps=_ps;
      
        for(uint256 i=0; i<_rules.length; i++){
          policies[_action][pointer].rules.push(_rules[i]);
        }
        policies[_action][pointer].isValued=true;
       
        return pointer;
    }

    // 精准匹配
    // todo:修改该函数 依据规则集合精准匹配策略 返回策略id
    function getPolicy(string memory _action, uint256 _id) public view returns(Policy memory){
        require(policies[_action][_id].isValued,"Error: The policy does not exist!");
        return policies[_action][_id];
    }

    // function getPolicyID(string memory _action, byte _ps, Rule[] memory rules) public view returns(uint _id){
    //     // 验重 也可以把验重放在应用层

    //     uint ruleSize=rules.length;
    //     uint policySize=getCurrentSize(_action);

    //     // todo
    //     for(uint i=0; i<policySize; i++) {
    //         if(policies[_action][i].ps == _ps) {
    //             for(uint j=0; j<ruleSize; j++) {
    //                 // do something
    //             }
    //         }
    //     }

    //     return _id;
    // }

    function deletePolicy(string memory _action, uint256 _id) public {
        require(msg.sender==owner, "Error: Only the SuperManager can add a policy");
        require(policies[_action][_id].isValued,"Error: The policy does not exist!");
         // update 2021/3/14
        if(Shared.stringCompare(_action,'r')){
            rSize--;
        }else if(Shared.stringCompare(_action, 'w')){
            wSize--;
        }else if(Shared.stringCompare(_action, 'e')){ 
            eSize--;
        }
        // update
        delete policies[_action][_id];
    }

    function updatePS(string memory _action, uint256 _id,  byte _ps) public {
        require(msg.sender==owner, "Error: Only the SuperManager can add a policy");
        require(policies[_action][_id].isValued,"Error: The policy does not exist!");
        policies[_action][_id].ps=_ps;
    }

    function updateSign(string memory _action, uint256 _id, Shared.Sign _sign) public{
        require(msg.sender==owner, "Error: Only the SuperManager can add a policy");
        require(policies[_action][_id].isValued,"Error: The policy does not exist!");
        policies[_action][_id].sign=_sign;
    }

    function getCurrentSize(string memory _action) internal view returns(uint size){
        if(Shared.stringCompare(_action,'r')){
            return rSize;
        }else if(Shared.stringCompare(_action, 'w')){
            return wSize;
        }else if(Shared.stringCompare(_action, 'e')){ 
            return eSize;
        }
    }

    // 属性匹配
    function getPolicyCheck(
        string memory _action, 
        address _subject, 
        address _object
    ) public view returns(Shared.Sign result){
        // todo: 暂时写死 属性不超过7个
        result=Shared.Sign.Deny; // deny可以表示没有匹配的策略或者决策结果为拒绝通过
        uint256 size=getCurrentSize(_action);
        
        byte subPS=dmc.getPS(_subject) & Shared.toByte(uint8(7)<<1);
        byte objPS=dmc.getPS(_object) & Shared.toByte(uint8(7)<<4);
        // 此时符号位为1 根据冲突模式的不同需要进行不同的处理
        byte _ps=subPS | objPS | 0x01;
        
        byte lrps=_ps;
        if(defaultMode==PolicyMode.AllowOverrides){
            lrps=lrps & 0xfe;
        }
        for(uint256 i=0; i<size; i++){ // 策略表遍历
            // 1. 前缀标记匹配
            if(policies[_action][i].ps | lrps == _ps){ 
                // 2.  属性匹配

                // 遍历策略的属性集合与访问请求的属性集合逐一对比
                uint256 j;
                uint256 len=policies[_action][i].rules.length;
                for(j=0; j<len; j++) {
                    uint8 attrId=policies[_action][i].rules[j].id;
                    string memory attrValue=policies[_action][i].rules[j].value;
                    if(!Shared.stringCompare(dmc.getAttribute(_subject, attrId),attrValue) 
                    && !Shared.stringCompare(dmc.getAttribute(_object, attrId),attrValue)) {
                        break;
                    }
                }
                // 属性完全匹配
                if(j==len){
                    // 策略遍历提前停止条件
                    if((defaultMode==PolicyMode.DenyOverrides 
                        && policies[_action][i].sign==Shared.Sign.Deny)
                        ||
                        (defaultMode==PolicyMode.AllowOverrides 
                        && policies[_action][i].sign==Shared.Sign.Allow)
                    ){
                        return policies[_action][i].sign;
                    }
                    result=policies[_action][i].sign;
                }
            }
        }
        return result;
    }

}
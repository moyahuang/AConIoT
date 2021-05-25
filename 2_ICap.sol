// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
import './1_Reputation.sol';

pragma experimental ABIEncoderV2;

contract ICap {

  // 为每一个根权能创建一个合约 一个根权能对应一个或一组设备资源 一个根权能关联其所有派生权能
  address owner;
  string[] actions; 
  Reputation public rc;

  // enum DelegationMode{TRANSFER,SHARE}
  // DelegationMode mode;

  // penalty thresholds
  uint Trev; 
  uint Tblock;
  uint Tauth;
  uint Tspan;

  struct Cap{
    bool right;
    bool delegationRight;
    bool revocationRight;
    uint depth;
    uint maxDepth;
    address parent;

    address[] children;
    address owner; //cap拥有者
    // bool isValid; // 传递非代理
    uint256 issuedate;
    uint256 expiredate;

    Credit credit;
    uint256 unblocktime;

    bool isValued;
  }

  struct Credit{
    uint256 score;
    uint256 updatedate;
  }

  struct BehaviorItem{
    uint id;
    string message;
  }

  struct Behaviors{
    BehaviorItem[] misbehaviors;
    BehaviorItem[] legalbehaviors;
  }

  mapping(address => mapping(string => Cap)) Caps; //Caps[address]["write"].delegation == "true"
  mapping(address => Behaviors) behaviors;

  event AccessRequest(address from, string action, bool permission, string reason, string penalty, uint credit);

  constructor(address _rc){
    owner = msg.sender;
    rc=Reputation(_rc);

    initPenaltyFactors();
    // mode= DelegationMode.SHARE;
  }

  function initPenaltyFactors() private {
    Trev = 50;
    Tblock = 55;
    Tauth = 58;
    Tspan = 300;
  }

  // 1. 创建新的token
  function createAction(string memory _action, uint _maxDepth) public{
     require(
      owner == msg.sender,
      "the caller is not the owner"
    );
    require(
      Caps[owner][_action].right == false,
      "action_name already exists"
    );
    Caps[owner][_action].right = true;
    Caps[owner][_action].delegationRight = true;
    Caps[owner][_action].revocationRight = true;
    Caps[owner][_action].depth = 0;
    Caps[owner][_action].maxDepth = _maxDepth;
    Caps[owner][_action].owner = msg.sender;
    Caps[owner][_action].issuedate = block.timestamp;
    Caps[owner][_action].expiredate = block.timestamp + 3600 * 24 * 7;
    Caps[owner][_action].credit = Credit(60, block.timestamp);
    Caps[owner][_action].unblocktime = block.timestamp;
    Caps[owner][_action].isValued = true;

  }
  // 2. token代理
  function delegation(
    address delegatee, 
    string memory _action, 
    bool _delegationRight,
    bool _revocationRight,
    uint _delegateTime
  ) public{
    require(
      Caps[delegatee][_action].right == false,
      "delegatee already have this action right"
    );
    require(
      Caps[msg.sender][_action].delegationRight == true,
      "'delegation' was called by a account who don't have delegationRight "
    );
    if(_revocationRight == true){
      require(
        Caps[msg.sender][_action].revocationRight == true,
        "The message sender doesn't have revocationRight"
      );
    }
  
    Caps[delegatee][_action].right = true;
    Caps[delegatee][_action].delegationRight = _delegationRight;
    Caps[delegatee][_action].revocationRight = _revocationRight;
    Caps[delegatee][_action].depth = Caps[msg.sender][_action].depth + 1;
    Caps[delegatee][_action].maxDepth = Caps[msg.sender][_action].maxDepth;
    Caps[delegatee][_action].parent = msg.sender;

    Caps[msg.sender][_action].children.push(delegatee);
    Caps[delegatee][_action].owner = delegatee;
    Caps[delegatee][_action].issuedate = _delegateTime;
    Caps[delegatee][_action].expiredate = Caps[msg.sender][_action].expiredate;
    Caps[delegatee][_action].credit = Credit(60, _delegateTime);
    Caps[delegatee][_action].unblocktime = _delegateTime;
    Caps[delegatee][_action].isValued = true;
    // uint credit = rc.reportBehavior(msg.sender, true, 1, "Delegation", _delegateTime);
    // Caps[delegatee][_action].credit.score = credit;
    // Caps[delegatee][_action].credit.updatedate = _delegateTime;

  }

  // 2.1 单个撤销
  function singleRevocation(address _revocatedAddress, string memory _action, uint _revTime) public{
    require(
      Caps[msg.sender][_action].revocationRight == true,
      "'singleRevocation' was called by a account who don't have revocationRight"
    );
    require(
      checkParent(msg.sender, _revocatedAddress, _action) == true,
      "'singleRevocation' was called by a account who is not parent"
    );

    for(uint i = 0; i < Caps[_revocatedAddress][_action].children.length; i++){
      Caps[Caps[_revocatedAddress][_action].parent][_action].children.push(Caps[_revocatedAddress][_action].children[i]);
      Caps[Caps[_revocatedAddress][_action].children[i]][_action].parent = Caps[_revocatedAddress][_action].parent; 
    }

    for(uint j = 0; j < Caps[Caps[_revocatedAddress][_action].parent][_action].children.length; j++){
      if(Caps[Caps[_revocatedAddress][_action].parent][_action].children[j] == _revocatedAddress){
        delete Caps[Caps[_revocatedAddress][_action].parent][_action].children[j];
        break;
      }
    }

    decrementDepth(_revocatedAddress, _action); 

    delete Caps[_revocatedAddress][_action];

    // uint credit = rc.reportBehavior(msg.sender, true, 2, "Revocation", _revTime);
    // Caps[msg.sender][_action].credit.score = credit;
    // Caps[msg.sender][_action].credit.updatedate = _revTime;
    // todo: 删除该主体行为记录
    // delete rc.behaviorsHashTable[_revocatedAddress];
  }

  function decrementDepth(address _target, string memory _action) private {
    // address[] memory tempChildren = Caps[_target][_action].children;
    for(uint i = 0; i < Caps[_target][_action].children.length; i++){
      decrementDepth(Caps[_target][_action].children[i], _action);
    }
    Caps[_target][_action].depth = Caps[_target][_action].depth - 1;
  }


  // 2.2 级联撤销
  function allChildrenRevocation(address _revocatedAddress, string memory _action) public{
    require(
      Caps[msg.sender][_action].revocationRight == true,
      "'allChildrenRevocation' was called by a account who don't have revocationRight"
    );
    require(
      checkParent(msg.sender, _revocatedAddress, _action) == true,
      "'allChildrenRevocation' was called by a account who is not parent"
    ); 

    // address tempParent = Caps[_revocatedAddress][_action].parent;
    for(uint j = 0; j < Caps[Caps[_revocatedAddress][_action].parent][_action].children.length; j++){
      if(Caps[Caps[_revocatedAddress][_action].parent][_action].children[j] == _revocatedAddress){
        delete Caps[Caps[_revocatedAddress][_action].parent][_action].children[j];
        // todo: 删除主体行为记录
        break;
      }
    }

    childrenRevocation(_revocatedAddress, _action);
  }

  function childrenRevocation(address _revocatedAddress, string memory _action) private{
    // address[] memory temp = Caps[_revocatedAddress][_action].children;
    for(uint i = 0; i < Caps[_revocatedAddress][_action].children.length; i++){
      childrenRevocation(Caps[_revocatedAddress][_action].children[i], _action);
    }
    delete Caps[_revocatedAddress][_action];
  }


  function checkParent(address _parent, address _child, string memory _action) private view returns(bool){
    bool checked = false;
    address temp = _child;


    for(uint i = 0; i < Caps[_child][_action].depth+1; i++){
      if(temp == _parent){
        checked = true;
        break;
      }else{
        temp = Caps[temp][_action].parent;
      }
    }

    return checked;
  }

  // 3. 查看token
  // function getCap(address _target, string memory _action) public view returns (bool, bool, bool, uint, uint, address, address[] memory){
  //   Cap memory temp = Caps[_target][_action];
  //   return (temp.right, temp.delegationRight, temp.revocationRight, temp.depth, temp.maxDepth, temp.parent, temp.children);
  // }

  function getCap(address _target, string memory _action) public view returns (Cap memory){
    return Caps[_target][_action];
  }

  // 4. token校验 由客体调用
  function accessRequest(address _subject, string memory _action, uint256 _accessTime) public returns(bool) {
    require(
      Caps[_subject][_action].isValued == true,
      "Error: Capability does not exist!"
    );
    require(
      _accessTime > Caps[_subject][_action].credit.updatedate,
      "Error: Unexpected access time! Check it again!"
    );
    uint credit;
    uint diff = _accessTime - Caps[_subject][_action].credit.updatedate; // 距离上次访问时间xxs
    string memory reason;
    string memory penalty;
    bool isIllegal=true;

    if(_accessTime > Caps[_subject][_action].expiredate) { // 权能过期
      allChildrenRevocation(_subject, _action);
      reason = "Capability expired!";
      penalty = "The capability and its dependents are revocated!";
      emit AccessRequest(_subject, _action, false, reason, penalty, credit);
      return true;
    }

    if (_accessTime < Caps[_subject][_action].unblocktime) { // 权能暂时被禁用
      credit = rc.reportBehavior(_subject, false, 1, "Access Attemp during Blocktime", _accessTime);
      reason = "Capability has been blocked, please try later!";
    } else {
      if(Caps[_subject][_action].right == false) {
        Caps[_subject][_action].right = true; // 解禁
      }

      if(diff > Tspan) {  // 上次访问时间大于五分钟
        credit = rc.reportBehavior(_subject, true, 0, "Access", _accessTime);
        reason = "Capability verified!";
        isIllegal = false;
      } else { // 上次访问时间小于五分钟
        credit = rc.reportBehavior(_subject, false, 0, "Frequent Access", _accessTime);
        reason = "Access too frequently!";
      }
    } 
    updateCredit(_subject, _action, credit, _accessTime);

    if(isIllegal) {
      penalty = exertPenalty(_subject, _action, credit, _accessTime);
    }
    emit AccessRequest(_subject, _action, Caps[_subject][_action].right, reason, penalty, credit);
    return true;
  }

  function updateCredit(address _subject, string memory _action, uint _newCredit, uint _accessTime) private{
    Caps[_subject][_action].credit.score = _newCredit;
    Caps[_subject][_action].credit.updatedate = _accessTime;
  }

  function exertPenalty(address _subject, string memory _action, uint _credit, uint _accessTime) private returns(string memory message) {
    if(_credit < Trev) {
      // 撤销当前权能
      singleRevocation(_subject, _action, _accessTime);
      message = "Capability too low! Capability revocated!";
    }
    if(_credit < Tblock) {
      // 禁止访问两小时
      Caps[_subject][_action].unblocktime = block.timestamp + 7200;
      Caps[_subject][_action].right = false;
      message = "Misbehaviors committed again! Capability blocked for two hours!";
    }
  
    if(_credit<Tauth) {
      // 撤销访问权
      Caps[_subject][_action].delegationRight = false;
      message = "The delegation right of the capability revocated!";
    }
    return message;
  }

  function getCredit (address _subject, string memory _action) public view returns (uint,uint) {
    return (Caps[_subject][_action].credit.score,Caps[_subject][_action].credit.updatedate);
  }

  function updatePenaltyFactors(string memory _name, uint _value) internal {
    require(msg.sender==owner, "Error: Only the owner can update penalty factors");
    if(stringCompare(_name, "rev")){
      Trev = _value;
    }

    if(stringCompare(_name, "block")){
      Tblock = _value;
    }

    if(stringCompare(_name, "auth")){
      Tauth = _value;
    }

    if(stringCompare(_name, "span")) {
      Tspan = _value;
    }
  }

  function stringCompare(string memory a, string memory b) internal pure returns (bool) {
        if (bytes(a).length != bytes(b).length) {
            return false;
        } else {
            return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
        }
    }
}


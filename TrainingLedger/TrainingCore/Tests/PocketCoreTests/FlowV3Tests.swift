import XCTest
import JavaScriptCore
@testable import PocketCore

final class FlowV3Tests: XCTestCase {
  func testCoachingDoesNotRequireEditorialAndAllowsExplicitAnswer() throws {
    for intent in [TutorIntent.coach, .answer, .step, .follow, .counterexample, .independent] {
      XCTAssertFalse(TutorProtocol.requiresOfficial(intent))
      XCTAssertEqual(TutorProtocol.allowedLevel(for:intent,currentHint:0),5)
    }
    XCTAssertTrue(TutorProtocol.requiresOfficial(.compare))
    XCTAssertEqual(TutorProtocol.allowedLevel(for:.nextHint,currentHint:0),1)
    XCTAssertEqual(TutorProtocol.allowedLevel(for:.translation,currentHint:4),0)
    let statement=try PocketCoreTests().statement()
    let json:[String:Any] = ["schemaVersion":1,"intent":TutorIntent.coach.rawValue,"problemID":statement.problem.id,"statementHash":statement.hash,"draftRevision":1,"revealLevel":5,"restatement":"","missingOrAssumed":[],"feedback":"你要求直接给答案：完整算法使用动态规划。\n```cpp\nint main() {}\n```","evidence":["基于题面独立推导，未执行"]]
    let answer=try JSONDecoder().decode(TutorResponse.self,from:JSONSerialization.data(withJSONObject:json))
    XCTAssertNoThrow(try TutorProtocol.validate(answer,intent:.coach,statement:statement,editorial:nil,revision:1,allowedLevel:5))
    XCTAssertThrowsError(try TutorOutputGuard.check("我已运行并且已通过所有测试",intent:.answer,level:5,original:""))
  }
  func testSubmissionOldArchiveStillDecodes() throws {
    let old=SubmissionAttempt(problem:try ProblemID(contest:4,index:"A"),revision:CodeRevision(source:"int main(){}",language:.cpp),handle:"fixture")
    var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(old)) as! [String:Any]
    object.removeValue(forKey:"sourceVerified")
    let read=try JSONDecoder().decode(SubmissionAttempt.self,from:JSONSerialization.data(withJSONObject:object))
    XCTAssertNil(read.sourceVerified);XCTAssertEqual(read.revision.source,old.revision.source)
  }
  func context(overrides:String="") throws -> JSContext {
    let js=try XCTUnwrap(JSContext())
    js.exceptionHandler={_,exception in XCTFail("JavaScript exception: \(exception?.toString() ?? "unknown")")}
    js.evaluateScript(#"""
      var window=globalThis, clicks=0, account='fixture', origin='https://codeforces.com';
      var location={origin:origin,href:origin+'/contest/4/submit/A'};
      class URL {
        constructor(value,base=location.href){
          this.href=value.startsWith('http')?value:(value.startsWith('/')?origin+value:base);
          const parts=this.href.match(/^(https?:\/\/[^/]+)([^?#]*)/);
          this.origin=parts[1];this.pathname=parts[2]||'/';this.username='';this.password='';
          this.searchParams={get:()=>null};
        }
      }
      class Event { constructor(name){this.name=name;} }
      class AbortController { constructor(){this.signal={};} abort(){} }
      const setTimeout=()=>1, clearTimeout=()=>{};
      const node=values=>({disabled:false,matches(s){return s===':disabled'&&this.disabled},dispatchEvent(){},getAttribute(){return null},...values});
      var field=node({name:'submittedProblemIndex',value:'A',tagName:'SELECT',options:[node({value:'A'})]});
      var lang=node({value:'x',options:[node({value:'new-dynamic-language'})]});
      var area=node({value:'',closest(){return form}});
      var csrf=node({value:'fixture-nonsecret'}),contest=node({value:'4'});
      var button=node({click(){clicks++}});
      var form={method:'post',getAttribute(){return '/contest/4/submit'},checkValidity(){return true},querySelector(s){
        if(s.includes('submittedProblem'))return field;
        if(s.includes('programTypeId'))return lang;
        if(s.includes('contestId'))return contest;
        if(s.includes('csrf_token'))return csrf;
        if(s.includes('type="submit"'))return button;
        return null;
      },querySelectorAll(s){return s.includes('type="submit"')?[button]:[]}};
      var document={baseURI:location.href,querySelector(s){if(s.includes('/logout'))return account?{}:null;if(s.includes('/profile/'))return {href:'https://codeforces.com/profile/'+account};if(s.includes('textarea'))return area;return null;},querySelectorAll(s){return s.includes('textarea')?[area]:[]}};
      var sessionStorage={values:{},setItem(k,v){this.values[k]=v},getItem(k){return this.values[k]||null}};
      var fetch=async()=>({ok:true,json:async()=>({status:'OK',result:[{id:90}]})});
      var input={contest:4,index:'A',id:'4A',source:'#include <iostream>\nint main(){}',language:'new-dynamic-language',handle:'fixture',nonce:'test-nonce'};
    """#)
    js.evaluateScript(overrides)
    return js
  }
  func evaluate(_ js:JSContext,body:String) throws -> [String:Any] {
    let done=expectation(description:"async JS")
    let callback:@convention(block) ()->Void={done.fulfill()}
    js.setObject(callback,forKeyedSubscript:"done" as NSString)
    js.evaluateScript("(async()=>{\(body)})().then(x=>{globalThis.result=x;done()},e=>{globalThis.result={exception:String(e)};done()})")
    wait(for:[done],timeout:3)
    let result=try XCTUnwrap(js.objectForKeyedSubscript("result")?.toDictionary() as? [String:Any])
    XCTAssertNil(result["exception"])
    return result
  }
  func testOfficialFormUsesDynamicLanguageAndClicksOnlyOnce() throws {
    let js=try context()
    let first=try evaluate(js,body:CFWebForm.dispatchBody)
    XCTAssertEqual(first["dispatched"] as? Bool,true)
    XCTAssertEqual(js.evaluateScript("clicks")?.toInt32(),1)
    XCTAssertEqual(js.evaluateScript("area.value")?.toString(),js.evaluateScript("input.source")?.toString())
    XCTAssertEqual(js.evaluateScript("lang.value")?.toString(),"new-dynamic-language")
    let second=try evaluate(js,body:CFWebForm.dispatchBody)
    XCTAssertEqual(second["error"] as? String,"ALREADY_SENT")
    XCTAssertEqual(js.evaluateScript("clicks")?.toInt32(),1)
  }
  func testChangedAccountWrongProblemMissingCSRFOrAPIErrorNeverPosts() throws {
    for override in ["account='another';", "contest.value='5';", "csrf.value='';", "fetch=async()=>({ok:false});", "lang.options=[];", "location.origin='https://example.com';"] {
      let js=try context(overrides:override)
      let result=try evaluate(js,body:CFWebForm.dispatchBody)
      XCTAssertNotNil(result["error"],override)
      XCTAssertEqual(js.evaluateScript("clicks")?.toInt32(),0,override)
    }
  }
  func testReceiptRequiresNewIDAndExactSourceAndSingleMatch() throws {
    let js=try context(overrides:#"""
      input.since=100; sessionStorage.setItem('cfpocket-test-nonce',JSON.stringify({ids:[90]}));
      var records=[{id:91,creationTimeSeconds:101,problem:{contestId:4,index:'A'},author:{members:[{handle:'fixture'}]}}];
      var remoteSource=input.source;
      class DOMParser {parseFromString(){return {querySelector(){return {textContent:remoteSource}}}}}
      fetch=async url=>({ok:true,json:async()=>({status:'OK',result:records}),text:async()=>'<pre id="program-source-text">fixture</pre>'});
    """#)
    XCTAssertEqual(try evaluate(js,body:CFWebForm.receiptBody)["id"] as? Int,91)
    js.evaluateScript("remoteSource='wrong source'")
    XCTAssertNil(try evaluate(js,body:CFWebForm.receiptBody)["id"])
    js.evaluateScript("remoteSource=input.source;records.push({...records[0],id:92})")
    XCTAssertEqual(try evaluate(js,body:CFWebForm.receiptBody)["ambiguous"] as? Bool,true)
    js.evaluateScript("records=[{...records[0],id:90}]")
    XCTAssertNil(try evaluate(js,body:CFWebForm.receiptBody)["id"])
    js.evaluateScript("records=[{...records[0],id:93,author:{members:[{handle:'other'}]}}]")
    XCTAssertNil(try evaluate(js,body:CFWebForm.receiptBody)["id"])
  }
}

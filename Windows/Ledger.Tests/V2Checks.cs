using CodexLedger;
public static class V2Checks {
    public static void Run(Action<bool,string> expect) {
        var start=DateTimeOffset.Parse("2026-10-04T00:00:00Z");var now=start.AddHours(1);
        LedgerTurn Turn(string id,string chat,string project,DateTimeOffset began)=>new(id,chat,id,"coding",new(100,10,10,1),began,began,true,1,0,"C:\\synthetic",new(project,project,"C:\\synthetic"),new[]{new UsageSample(id,chat,id,id,began,"gpt-5.4",new(100,10,10,1))},[]){StartedAt=began};
        var first=Turn("t1","chat1","project1",start);var second=Turn("t2","chat2","project1",start.AddMinutes(1));var third=Turn("t3","chat3","project2",start.AddMinutes(2));
        var turns=new[]{first,second,third};var book=new GoalBook{Goals=new(){new("a","Outcome A",start),new("b","Outcome B",start)}};
        AttributionRule Rule(string id,string kind,string target,string goal,string mode,string[]? ids=null,DateTimeOffset? from=null)=>new(id,new(kind,target),goal,mode,(ids??[]).ToHashSet(),from,null,start);
        book.Apply(Rule("fixed","project","project1","a","selected",new[]{first.ID}));
        expect(book.Owner(first)=="a"&&book.Owner(second)==null,"fixed historical set excludes other work");
        var future=Turn("future","chat1","project1",now.AddMinutes(1));expect(book.Owner(future)==null,"fixed set excludes future starts");
        var continuous=Rule("continuous","project","project1","b","fromDate",from:start) with{SavedAt=start.AddMinutes(1)};
        var preview=book.Preview(continuous,turns);expect(!preview.Displaced.ContainsKey("a")&&preview.Cost==second.Cost,"preview respects fixed turn precedence and exact money");
        book.Apply(continuous);expect(book.Owner(first)=="a","fixed historical work has turn precedence");
        book.Apply(Rule("new-fixed","project","project1","b","selected",new[]{first.ID}) with{SavedAt=start.AddMinutes(2)});expect(book.Owner(first)=="b","latest fixed selection wins");
        book.Apply(Rule("chat","conversation","chat1","a","selected",new[]{first.ID}) with{SavedAt=start.AddMinutes(3)});expect(book.Owner(first)=="a","conversation takes precedence");
        book.Apply(Rule("turn","turn","t1","b","selected",new[]{first.ID}) with{SavedAt=start.AddMinutes(4)});expect(book.Owner(first)=="b","turn takes precedence");
        book.Complete("b",turns,now,start,new("partial",new[]{"conflict"}));expect(book.Goals[1].Completions.Count==0,"partial records cannot complete");
        book.Complete("b",turns,now,start,new("complete",[]));var frozen=book.Goals[1].Completions[0];
        expect(book.Owner(future)==null,"completion stops future starts");
        expect(book.Owner(second with{Date=now.AddDays(1)})=="b","response slice preserves stable owner");
        book.Reopen("b");expect(book.Goals[1].Completions[0].ID==frozen.ID&&book.Owner(future)==null,"reopen preserves history and stopped rules");
        book.Complete("b",turns,now.AddMinutes(2));expect(book.Goals[1].Completions.Count==2&&book.Goals[1].Completions[0].Cost==frozen.Cost,"recompletion preserves frozen previous price");
        var decoded=GoalArchive.Decode(GoalArchive.Encode(book));expect(decoded.Rules.Count==book.Rules.Count&&decoded.Goals[1].Completions[0].Cost==frozen.Cost,"v2 records roundtrip exactly");
        var unknown=first with{Samples=new[]{new UsageSample("unknown","chat1","t1","t1",start,"unknown-model",new(99))},Usage=new(99)};
        book.Complete("b",new[]{unknown},now.AddMinutes(3));expect(book.Goals[1].Completions.Last().Cost.UnpricedTokens==99,"unknown pricing preserves unpriced completion");
        book.Apply(Rule("exclude","turn","t1",GoalBook.Unassigned,"selected",new[]{first.ID}) with{SavedAt=now});expect(book.Owner(first)==null,"explicit exclusion overrides parent assignment");
        expect(turns.Where(t=>book.Owner(t)!=null).Sum(t=>t.Usage.Total)+turns.Where(t=>book.Owner(t)==null).Sum(t=>t.Usage.Total)==turns.Sum(t=>t.Usage.Total),"goals plus unassigned reconcile");
    }
}

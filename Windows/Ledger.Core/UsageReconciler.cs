namespace CodexLedger;

public static class UsageReconciler {
    public static (List<UsageSample> Samples,List<string> Warnings,List<DateTimeOffset> Dates) Reconcile(IReadOnlyList<UsageSample> legacy,IReadOnlyList<UsageSample> modern,IReadOnlyDictionary<string,DateTimeOffset> intervals) {
        if(modern.Count==0)return(legacy.ToList(),[],[]);
        var residuals=new List<UsageSample>();var warnings=new HashSet<string>();var dates=new HashSet<DateTimeOffset>();
        foreach(var old in legacy) {
            var start=intervals.GetValueOrDefault(old.ID,DateTimeOffset.MinValue);
            var covered=modern.Where(s=>s.Date>start&&s.Date<=old.Date).ToArray();
            var used=covered.Aggregate(new TokenUsage(),(a,s)=>a+s.Usage);
            if(used.Input>old.Usage.Input||used.Output>old.Usage.Output){warnings.Add("新旧日志计数无法对齐，用量可能不完整。");dates.Add(old.Date);dates.UnionWith(covered.Select(s=>s.Date));continue;}
            long input=old.Usage.Input-used.Input,output=old.Usage.Output-used.Output;
            var remainder=new TokenUsage(input,Math.Min(input,Math.Max(0,old.Usage.Cached-used.Cached)),output,Math.Min(output,Math.Max(0,old.Usage.Reasoning-used.Reasoning)));
            if(remainder.Total>0)residuals.Add(old with{Usage=remainder,HasRequestUsage=old.HasRequestUsage&&covered.Length==0});
        }
        foreach(var turn in legacy.Select(s=>s.TurnID).Intersect(modern.Select(s=>s.TurnID))) {
            var a=legacy.Where(s=>s.TurnID==turn).Aggregate(new TokenUsage(),(u,s)=>u+s.Usage);
            var b=modern.Where(s=>s.TurnID==turn).Aggregate(new TokenUsage(),(u,s)=>u+s.Usage);
            if(a.Input==b.Input&&a.Output==b.Output&&residuals.Any(s=>s.TurnID==turn)){residuals.RemoveAll(s=>s.TurnID==turn);warnings.Add("新旧日志计数无法对齐，用量可能不完整。");dates.UnionWith(legacy.Concat(modern).Where(s=>s.TurnID==turn).Select(s=>s.Date));}
        }
        return(modern.Concat(residuals).OrderBy(s=>s.Date).ThenBy(s=>s.ID,StringComparer.Ordinal).ToList(),warnings.Order(StringComparer.Ordinal).ToList(),dates.Order().ToList());
    }
}

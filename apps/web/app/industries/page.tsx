const industries = [
  ['Hospitality','Banquet, housekeeping support, stewarding, service and guest-facing operations.'],
  ['Food & Beverage','Service crew, runners, kitchen support and peak-period staffing.'],
  ['Cleaning','Commercial and hospitality cleaning with role and training readiness.'],
  ['Retail','Sales support, replenishment, queue management and seasonal manpower.'],
  ['Promotions','Brand ambassadors, roadshows, launches and customer acquisition teams.'],
  ['Events','Registration, ushers, event crew, logistics support and venue operations.'],
];

export default function Industries() {
  return <main style={{minHeight:'100vh',background:'#F7F8FB',color:'#101828',padding:'64px 24px'}}>
    <section style={{maxWidth:1080,margin:'0 auto'}}>
      <a href="/" style={{color:'#344054',textDecoration:'none',fontWeight:800}}>QY Workforce</a>
      <div style={{marginTop:40,color:'#4D63FF',fontWeight:850,fontSize:12,letterSpacing:1.3}}>INDUSTRIES</div>
      <h1 style={{fontSize:'clamp(38px,6vw,68px)',lineHeight:1.04,letterSpacing:'-.045em',maxWidth:850,margin:'9px 0 16px'}}>Built for labour-intensive operations where fill rate matters.</h1>
      <p style={{fontSize:18,color:'#667085',lineHeight:1.6,maxWidth:760}}>QY Workforce helps operators source suitable casual workers while keeping attendance, approvals and margin visibility in one workflow.</p>
      <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(280px,1fr))',gap:14,marginTop:40}}>{industries.map(([name,desc])=><article key={name} style={{background:'#fff',border:'1px solid #E4E7EC',borderRadius:18,padding:24}}><h2 style={{margin:'0 0 10px',fontSize:21}}>{name}</h2><p style={{margin:0,color:'#667085',lineHeight:1.55,fontSize:14}}>{desc}</p></article>)}</div>
      <div style={{marginTop:34,display:'flex',gap:12,flexWrap:'wrap'}}><a href="/?intent=employer" style={{background:'#111827',color:'#fff',padding:'13px 18px',borderRadius:10,textDecoration:'none',fontWeight:800}}>Request manpower</a><a href="/how-it-works" style={{background:'#fff',border:'1px solid #D0D5DD',color:'#344054',padding:'13px 18px',borderRadius:10,textDecoration:'none',fontWeight:800}}>How it works</a></div>
    </section>
  </main>
}

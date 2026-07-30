from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_CELL_VERTICAL_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from pathlib import Path

OUT = str(Path(__file__).resolve().parent / 'IaC_Demo_Hourly_Cost_Printout.docx')
BLUE='2E74B5'; DARK='1F4D78'; LIGHT='E8EEF5'; GREEN='1F5E35'; GOLD='7A5A00'

def shade(c, fill):
    x=c._tc.get_or_add_tcPr(); s=OxmlElement('w:shd'); s.set(qn('w:fill'),fill); x.append(s)
def margins(c):
    x=c._tc.get_or_add_tcPr(); m=OxmlElement('w:tcMar')
    for side,val in [('top',100),('start',120),('bottom',100),('end',120)]:
        n=OxmlElement('w:'+side); n.set(qn('w:w'),str(val)); n.set(qn('w:type'),'dxa'); m.append(n)
    x.append(m)
def font(r,size=11,color='222222',bold=False):
    r.font.name='Calibri'; r._element.get_or_add_rPr().rFonts.set(qn('w:ascii'),'Calibri'); r._element.get_or_add_rPr().rFonts.set(qn('w:hAnsi'),'Calibri'); r.font.size=Pt(size); r.bold=bold; r.font.color.rgb=RGBColor.from_string(color)
def para(d,s='',after=6,before=0):
    p=d.add_paragraph(); p.paragraph_format.space_before=Pt(before); p.paragraph_format.space_after=Pt(after); p.paragraph_format.line_spacing=1.1
    if s: font(p.add_run(s))
    return p
def head(d,s,level=1):
    p=d.add_paragraph(style='Heading %d'%level); font(p.add_run(s),16 if level==1 else 13,BLUE if level<3 else DARK,True); return p
def table(d,hs,rows,widths):
    t=d.add_table(rows=1,cols=len(hs)); t.alignment=WD_TABLE_ALIGNMENT.LEFT; t.autofit=False
    for i,h in enumerate(hs):
        c=t.rows[0].cells[i]; c.width=Inches(widths[i]); c.vertical_alignment=WD_CELL_VERTICAL_ALIGNMENT.CENTER; margins(c); shade(c,LIGHT); p=c.paragraphs[0]; p.paragraph_format.space_after=Pt(0); font(p.add_run(h),9.5,DARK,True)
    for row in rows:
        cs=t.add_row().cells
        for i,v in enumerate(row):
            cs[i].width=Inches(widths[i]); cs[i].vertical_alignment=WD_CELL_VERTICAL_ALIGNMENT.CENTER; margins(cs[i]); p=cs[i].paragraphs[0]; p.paragraph_format.space_after=Pt(0); p.paragraph_format.line_spacing=1.0; font(p.add_run(v),9.5)
    return t

d=Document(); sec=d.sections[0]
for a in ['top_margin','bottom_margin','left_margin','right_margin']: setattr(sec,a,Inches(1))
sec.header_distance=sec.footer_distance=Inches(.492)
s=d.styles['Normal']; s.font.name='Calibri'; s.font.size=Pt(11); s.paragraph_format.space_after=Pt(6); s.paragraph_format.line_spacing=1.1
for n,sz,col,bef,aft in [('Heading 1',16,BLUE,16,8),('Heading 2',13,BLUE,12,6)]:
    x=d.styles[n]; x.font.name='Calibri'; x.font.size=Pt(sz); x.font.bold=True; x.font.color.rgb=RGBColor.from_string(col); x.paragraph_format.space_before=Pt(bef); x.paragraph_format.space_after=Pt(aft); x.paragraph_format.keep_with_next=True

p=d.add_paragraph(); p.paragraph_format.space_after=Pt(3); font(p.add_run('IaC Demo Resource Cost Printout'),24,'0B2545',True)
p=d.add_paragraph(); p.paragraph_format.space_after=Pt(14); font(p.add_run('Estimated average cost for one complete running hour'),15,BLUE)
para(d,'Scope: Azure resources defined in the Demo-IaC repository. Levels are cumulative: L2 includes L1, L3 includes the earlier foundation, and L4 adds the second-region and global-access components.')

head(d,'Executive summary')
table(d,['Level','Incremental cost added by level','Estimated total cost for one hour'],[
('L1 - Hub and spoke','$0.25/hr','$0.25/hr'),('L2 - Web tier and firewall','$0.57/hr','$0.82/hr'),('L3 - Containers and data','$0.08/hr','$0.90/hr'),('L4 - Global scale','$0.06/hr','$0.96/hr')],[1.65,2.25,2.60])
para(d,'Planning figure: approximately $1.00 for one hour with the full L4 stack running, before traffic, log ingestion, backups, or unusual data transfer. Actual billing may vary by subscription agreement, region, currency, VM price, and usage.')

head(d,'Cost progression by level')
for title,body in [
('L1 - Hub and spoke | approximately $0.25 per hour','L1 contains one Standard_B2s Linux VM, one Basic Bastion host, a Standard public IP used by Bastion, and two virtual networks with peering. VNets and NSGs are generally not hourly charges. The VM and Bastion are the main always-on costs.'),
('L2 - Web tier and firewall | approximately $0.82 per hour total','L2 retains L1 and adds three Standard_B2s Linux VMs, three operating-system disks, an internal Standard Load Balancer, an Azure Firewall Standard instance, and the firewall public IP. The firewall is the dominant new cost; the three VMs are the next largest addition.'),
('L3 - Containers and data | approximately $0.90 per hour total','L3 adds a Container Apps environment and one minimum-size container replica, Azure SQL Database Basic, two private endpoints, Key Vault, private DNS, Log Analytics, Application Insights, a managed identity, and alerting. The estimate assumes very light demo traffic and negligible log ingestion.'),
('L4 - Global scale | approximately $0.96 per hour total','L4 adds a second-region Container Apps environment and one minimum-size replica, a secondary SQL server/failover configuration, and Azure Front Door Standard. Front Door has a base hourly charge; requests and data transfer are additional usage meters.')]:
    head(d,title,2); para(d,body)

head(d,'Illustrative resource breakdown')
table(d,['Resource group / level','Resources counted','Approx. hourly amount'],[
('L1','1 B2s VM + disk; Basic Bastion; Bastion public IP','$0.25'),
('L2 incremental','3 B2s VMs + disks; Azure Firewall Standard; firewall public IP; Standard Load Balancer','$0.57'),
('L3 incremental','Container Apps; Basic SQL database; private endpoints; monitoring and platform services','$0.08'),
('L4 incremental','Secondary Container App; Front Door Standard; failover-related services','$0.06'),
('Full L4 stack','All resources from L1 through L4','$0.96')],[1.50,3.65,1.35])

head(d,'Assumptions behind the estimate')
for x in ['Region: East US 2 for L1-L3, with West US 2 as the L4 secondary region, matching the Bicep defaults.','Pricing basis: approximate US pay-as-you-go list pricing, rounded for presentation use.','VMs run for the entire hour and are not deallocated. Standard_LRS OS disks are included as a small hourly equivalent.','Container Apps run at the configured minimum of one 0.5 vCPU / 1 GiB replica per region.','L3 assumes a Basic 5-DTU Azure SQL database and minimal data storage, backups, requests, and log ingestion.','Network traffic, NAT/data processing, SQL backup growth, Log Analytics ingestion, Application Insights telemetry, and Front Door requests/data transfer are excluded or assumed negligible.','The optional L1 VPN Gateway is not included because it is commented out in the template.']:
    p=d.add_paragraph(style='List Bullet'); p.paragraph_format.left_indent=Inches(.5); p.paragraph_format.first_line_indent=Inches(-.25); p.paragraph_format.space_after=Pt(4); font(p.add_run(x))

head(d,'Important cost notes')
para(d,'Azure Firewall and Bastion continue billing while deployed, even if the demo is idle. The repository includes a teardown workflow; use it after the demonstration or when the environment is not needed. For a live presentation, budget a small buffer above the table, such as $1.25-$1.50 for a full L4 hour, to cover normal request and telemetry activity.')
para(d,'These are planning estimates, not an invoice or quote. Azure pricing pages state that displayed prices can vary by agreement, date, currency, and region. Confirm the final amount with the Azure Pricing Calculator or the subscription Cost Management view before presenting a committed budget.')

head(d,'Reference links')
for label,url in [('Azure pricing overview','https://azure.microsoft.com/pricing/'),('Azure Firewall pricing','https://azure.microsoft.com/pricing/details/azure-firewall/'),('Azure Bastion pricing','https://azure.microsoft.com/pricing/details/azure-bastion/'),('Azure SQL Database pricing','https://azure.microsoft.com/pricing/details/azure-sql-database/single/'),('Azure Front Door pricing','https://azure.microsoft.com/pricing/details/frontdoor/')]:
    p=d.add_paragraph(); p.paragraph_format.space_after=Pt(3); r=p.add_run(label+': '+url); font(r,9,'555555')

f=sec.footer.paragraphs[0]; f.alignment=WD_ALIGN_PARAGRAPH.RIGHT; font(f.add_run('IaC Demo | Cost Printout'),9,'777777')
d.core_properties.title='IaC Demo Resource Cost Printout'; d.core_properties.subject='Approximate one-hour Azure resource cost by cumulative lab level'; d.save(OUT); print(OUT)

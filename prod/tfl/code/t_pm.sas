/*****************************************************************************\
*  ____                  _
* |  _ \  ___  _ __ ___ (_)_ __   ___
* | | | |/ _ \| '_ ` _ \| | '_ \ / _ \
* | |_| | (_) | | | | | | | | | | (_) |
* |____/ \___/|_| |_| |_|_|_| |_|\___/
* ____________________________________________________________________________
* Sponsor              : C999
* Study                : PILOT01
* Program              : t_pm.sas
* Purpose              : Create Summary of Prior Medications 
* ____________________________________________________________________________
* DESCRIPTION                                                    
*                                                                   
* Input files: None
*              
* Output files: t_pm.rtf and t_pm.sas7bdat
*               
* Macros: init scanlog, p_rtfCourier
*         
* Assumptions: 
*
* ____________________________________________________________________________
* PROGRAM HISTORY                                                         
*  31MAY2022             | Ugo Anozie          | Original version
\*****************************************************************************/

*********;
%include "!DOMINO_WORKING_DIR/config/domino.sas";
*********;

**** USER CODE FOR ALL DATA PROCESSING **;

%let outname    = t_pm;
%let tflid      = t_pm;
%let tflnum      = 14.7.5;

*create Big N macro variables;
data bigN_mac;
  set adamw.adsl (where = ((SAFFL = 'Y'))) end = eof;
  retain npl ndum ndumax;
  if _N_ = 1 then do;
    npl = 0;
	ndum = 0;
    ndumax=0;
	end;
  if trt01an = 0 then npl = npl + 1;
  if trt01an = 54 then ndum = ndum + 1;
  if trt01an = 81 then ndumax = ndumax + 1;
  if eof then do;
    call symput('npl', strip(put(npl, 8.)));
    call symput('ndum', strip(put(ndum, 8.)));
	call symput('ndumax', strip(put(ndumax, 8.)));
	call symput('tot', strip(put((ndumax + ndum + npl), 8.)));
	end;
run;

*dataset containing big N counts;
data adsl_tot;
  set adamw.adsl (where = ((saffl = 'Y')));
  output;
  trt01an=100;
  trt01a="Total";
  output;
run;


proc freq data = adsl_tot noprint;
  table studyid*trt01an / out= BigN (rename = (count = n trt01an=trtan) drop=percent where = (trtan ne .));
run;

*read in adcm;
proc sort data = adamw.adcm (where = (prefl='Y'))
          out = fromCM;
  by cmdecod cmclas cmstdtc astdt;
run;

*add value for total count;
data cm_total;
  set fromCM;
  output;
  trtan=100;
  trta="Total";
  output;
run;

*get counts using CMCLAS and CMDECOD. Both variables will need confirmation;
proc sql noprint;
  create table row1_db as
  select TRTaN, count(distinct(usubjid)) as CNT, "Any medication" as rowlbl1 LENGTH = 200, 0 as rowgrp1 
  from cm_total
  group by TRTaN;

  create table db_atc1 as  
  select TRTaN, cmclas, count(distinct(usubjid)) as CNT, "Any medication" as rowlbl1 LENGTH = 200 
  from cm_total
  group by TRTaN, cmclas;

  create table db_pts as  
  select TRTaN, cmclas, cmdecod, count(distinct(usubjid)) as CNT, cmdecod as rowlbl1 LENGTH = 200 
  from cm_total
  group by TRTaN, cmclas, cmdecod;

quit;

*create order variable for CMCLAS terms;
proc sort data = db_atc1 out = db_atc1_unq (keep = cmclas) nodupkey ;
  by cmclas;
run;

*order variable;
data db_soc_ord;
  set db_atc1_unq;
  rowgrp1 = _n_;
run;

*merge order variable on the db_atc1 and  db_pts datasets;
proc sql noprint;
  create table atc1_fin as
  select a.*, b.rowgrp1
  from db_atc1 as a
  left join db_soc_ord as b
  on a.cmclas=b.cmclas;

  create table pts_fin as
  select a.*, b.rowgrp1
  from db_pts as a
  left join db_soc_ord as b
  on a.cmclas=b.cmclas;
quit;

*set all 3 main datasets;
data all_cm;
  set row1_db atc1_fin pts_fin;
run;

*calculate percent values;
proc sort data = all_cm out= all_cm_srt;
   by trtan;
run;

data allcm_percent;
   length pct $20;
   merge all_cm_srt (in=a ) bign (in=b);
   by trtan;
   if a ;

   if cnt ne . and cnt = n then pct  = put(cnt, 3.) ||" ("|| put(cnt/n*100, 3.)||"%)";
   else if (int(log10(round(cnt/n*100, 0.1)))+1) >=2 and cnt ne . and cnt ne n then pct  = put(cnt, 3.) ||" ("|| strip(put(round(cnt/n*100, 0.1), 4.1))||"%)";
   else if (int(log10(round(cnt/n*100, 0.1)))+1) <2 and cnt ne . and cnt ne n then pct  = put(cnt, 3.) ||"  ("|| strip(put(round(cnt/n*100, 0.1), 4.1))||"%)";
   else pct = " 0";

   if index(pct, ".00") > 0 then pct = tranwrd (pct, ".00", "");
run;

proc sort data = allcm_percent out = allcm_percent_srt;
  by rowgrp1 cmdecod rowlbl1  cmclas trtan pct;
run;

proc transpose data = allcm_percent_srt out= alltransp;
  by rowgrp1 cmdecod rowlbl1  cmclas;
  id trtan;
  var PCT;
run;

*include another order variable and create col1-col vars;
data cm_final;
  attrib rowlbl1   length = $200     label='ATC Level 1 |n Ingredient'
		 col1   length = $200     label="Placebo |n (N=&npl.)   |n n(%)"
         col2   length = $200     label="Xanomeline Low Dose |n (N=&ndum.)   |n n(%)"
		 col3   length = $200     label="Xanomeline High Dose |n (N=&ndumax.)   |n n(%)"
         col4   length = $200     label="Total |n (N=&tot.)   |n n(%)";

  set alltransp
      db_soc_ord(in=a);

	  rowgrp2=rowgrp1;

	  if a then do; rowlbl1=cmclas; rowgrp2= rowgrp2-0.5; end;

	  if not a and rowgrp1^=0 then rowlbl1="  "!!rowlbl1;

	  col1=_0;
	  col2=_54;
	  col3=_81;
	  col4=_100;

	  *force in zeros where values are missing;
	  array zero {*} col1-col3;
		   do i =1 to dim(zero) ;
		      if zero {i} eq '' and rowgrp1=rowgrp2 then zero {i} = "  0";
			end;

	 *create page variable;
			if rowgrp1<=5 then rowgrp3=1;
			else rowgrp3=2;

	  drop _name_ i _:;
run;
   
*sort before proc report; 

proc sort data=cm_final out=t_pm;
  by rowgrp1 rowgrp2 cmdecod rowlbl1  cmclas;
run;


%p_rtfCourier();
title; footnote;

options orientation = landscape nodate nonumber;
ods rtf file = "&__env_runtime.&__delim.prod&__delim.tfl&__delim.output&__delim.&outname..rtf" style = rtfCourier ;
ods escapechar = '|';

    /* Titles and footnotes for PROC REPORT */
    title1 justify=l "Protocol: CDISCPILOT01" j=r "Page |{thispage} of |{lastpage}" ;
    title2 justify=l "Population: Safety" ;
    title3 justify=c "Table &tflnum." ;
	title4 justify=c "Summary of Prior Medications" ;

    footnote1 justify=l "A medication may be included in more than one ATC level category and appear more than once.";
    footnote2 justify=l "Percentages are based on the number of subjects in the safety population within each treatment group.";
    footnote3 ;
    footnote4 justify=l "Source: &__full_path, %sysfunc(date(),date9.) %sysfunc(time(),tod5.)" ;

    proc report data = t_pm split = '~'
            style = rtfCourier
            style(report) = {width=100%} 
            style(column) = {asis = on just = l}
            style(header) = {bordertopcolor = black bordertopwidth = 3 just = c}
            spanrows;
  
            

            column rowgrp3 rowgrp1 rowgrp2 cmdecod rowlbl1 col1-col4 ;

            define rowgrp1         / order order = data noprint;
			define rowgrp2         / order order = data noprint;
			define rowgrp3         / order order = data noprint;
			define cmdecod         / order = data noprint;

            define rowlbl1      /  order=data
                                    style(header) = {borderbottomcolor = black borderbottomwidth = 3 width = 50% just = l};
            define col1    /  order = data 
                                    style(header) = {borderbottomcolor = black borderbottomwidth = 3 width = 12%} style(column) = {leftmargin = 1% };
            define col2  /  order = data 
                                    style(header) = {borderbottomcolor = black borderbottomwidth = 3 width = 12%} style(column) = {rightmargin = 1%};
            define col3   /  order = data 
                                    style(header) = {borderbottomcolor = black borderbottomwidth = 3 width = 12%} style(column) = {leftmargin = 1% };
			define col4   /  order = data 
                                    style(header) = {borderbottomcolor = black borderbottomwidth = 3 width = 12%} style(column) = {leftmargin = 1% };
            
            compute before rowgrp1;
                line ' ';
            endcomp;

            compute after rowgrp3 / style = {borderbottomcolor = black borderbottomwidth = 3};
                line ' ';
            endcomp;


			break after rowgrp3 / page ;

            
    run;
    
ods rtf close; 
title; footnote;

**** END OF USER DEFINED CODE **;

********;
**%scanlog;
********;

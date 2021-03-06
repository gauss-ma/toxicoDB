#!/bin/bash
ToxDB_out="Tox.db"
ToxDB_in="Rechazados_CID.lst" #"lista.lst" #"Rechazados_ChemIDPlus.lst" #"lista.lst"

IFS=$'\n' CASs=($(awk -F ";" '{print $1}' ${ToxDB_in}))
IFS=$'\n' nombres=($(awk -F ";" '{print $2}' ${ToxDB_in}))

for i in $(seq 0 ${#CASs[@]})
do
	cas=${CASs[i]}
	nombre=${nombres[i]}

        echo -en "${nombre} \e[31m ${cas} : \e[0m"

	#=>Buscar CIDs:
        tmp_json=$(curl -s "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/xref/rn/${cas}/cids/JSON")
	if [ $? -eq 0 ]
        then
        	cid=$(echo $tmp_json | jq -r '.IdentifierList.CID[0]')
		echo $cid >> cid.lst
		echo -e "\e[32m $cid \e[0m"
        else
        	echo -e "\e[31m CID no encontrado.\e[0m"; echo "${cas};${nombre}">> Rechazados_CID.lst
		continue
        fi;
		printf " {\n"						    >> $Linker_out
			printf "   \"CID\" : ${cid},\n" 		    >> $Linker_out
			printf "   \"CAS\" : \"${cas}\",\n" 		    >> $Linker_out
			printf "   \"nombre\" : \"${nombre}\",\n" 	    >> $Linker_out
		printf " },\n" 						    >> $Linker_out
	#------------------------------------------------------------------------------------------------------------------------------
	#=>PubChem:
        #Imagen de estructura 2D y 3D:
		img2D_file="PubChem/img2D/${cid}.png";img3D_file="PubChem/img3D/${cid}.png"
		imgNotAvail_file="PubChem/img3D/NotAvailable.png";imgNoDispon_file="PubChem/img3D/NoDisponible.png"
                wget --quiet -O "${img2D_file}" "https://pubchem.ncbi.nlm.nih.gov/image/imgsrv.fcgi?cid=${cid}&t=s"
                wget --quiet -O "${img3D_file}" "https://pubchem.ncbi.nlm.nih.gov/image/img3d.cgi?&cid=${cid}&t=s"
                #Cambio fondo blanco por transparente y pos-procesamiento:
                convert ${img2D_file} -transparent "#F5F5F5" ${img2D_file}
		compare -metric AE ${imgNotAvail_file} ${img3D_file} null
		if [ $? -eq 0 ]
		then
			cp ${imgNoDispon_file} ${img3D_file}
		else
			convert ${img3D_file} -transparent white ${img3D_file}
		fi;

		#Sinonimos:
	        tmp_json=$(curl "https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound/${cid}/JSON?heading=Synonyms")
		sinonimos=$(echo $tmp_json | jq "[.. | ."String"? | strings][0:9]")
		#Descripcion:
	        tmp_json=$(curl "https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound/${cid}/JSON?heading=Hazards+Summary")
		descripcion=$(./trans --brief en:es <<< $(echo $tmp_json | jq '..|."String" ? | strings' | sed -e ':a;N;$!ba;s/\"//g;s/\n/<br>/'))
		#Seguridad Química:
                tmp_json=$(curl "https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound/${cid}/JSON?heading=Chemical+Safety")
		GHSs="$(echo $tmp_json | jq '.. | ."Extra"? |strings' | awk -F '\n' 'BEGIN{printf "["};{printf("%s,", $1)};END{printf "],\n"}')"
		#NFPA 704 diamond
		tmp_json=$(curl "https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound/${cid}/JSON?heading=NFPA+Hazard+Classification")
		NFPA="$(echo $tmp_json | jq '[.. | ."Extra"? |strings][0]')"

		#Print en ToxDB:
		printf " {\n"						    >> $PubChem_out
			printf "   \"CID\" : ${cid},\n" 		    >> $PubChem_out
			printf "   \"GHS\" : ${GHSs}\n"			    >> $PubChem_out 
			printf "   \"NFPA\" : ${NFPA},\n"		    >> $PubChem_out 
			printf "   \"descripcion\" : ${descripcion},\n"     >> $PubChem_out 
			printf "   \"sinonimos\" : ${sinonimos},\n"         >> $PubChem_out 
		printf " },\n" 						    >> $PubChem_out
	#------------------------------------------------------------------------------------------------------------------------------
	#=>ChemIDPlus: 
	#FísicoQuímica y Toxicología
        	tmp_json=$(curl "https://chem.nlm.nih.gov/api/data/rn/sw/${cas}/?data=details")
		if [ $? -eq 0 ]
                then
                	fisicoquimica=$(echo $tmp_json | jq -r '.results[0].physicalProps')
                	toxicologia=$(  echo $tmp_json | jq -r '.results[0].toxicityList')
                	#echo -e "\e[35m $fisicoquimica \e[0m"; 	echo -e "\e[35m $toxicologia \e[0m"
                else
                	echo -e "\e[31m ChemIDPlus data no encontrado.\e[0m"; echo "${cas};${nombre}" >> Rechazados_ChemIDPlus.lst
			continue
                fi;

		printf " {\n"						    >> $ChemIDPlus_out
			printf "   \"CAS\" : \"${cas}\",\n" 		    >> $ChemIDPlus_out
			printf "   \"FisProps\": ${fisicoquimica},\n"       >> $ChemIDPlus_out
			printf "   \"ToxProps\": ${toxicologia},\n" 	    >> $ChemIDPlus_out
		printf " },\n" 						    >> $ChemIDPlus_out
	#------------------------------------------------------------------------------------------------------------------------------


done;
	#=>PubChem: Summary
		props="MolecularFormula,MolecularWeight,IUPACName,InChI,InChIKey,XLogP,CanonicalSMILES,Charge,Fingerprint2D"
		cids=$(cat cid.lst | awk '{printf $1","}END{print "\n"}' | sed -e 's/null//g;s/\,*$//g;s/\,\,*/\,/g;')
		curl "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/${cids_str}/property/${props}/JSON" > summary_db.json

	#Merge jsons:
		#jq -s '.[0] * .[1]' file1 file2


	# ----
	#POST-Procesamiento:
	#Bug en ChemIDPlus, doble "" en cita a bibliografía.
	printf "TOXDB=[\n" >${ToxDB_out}.js
	sed "s/\(\"t\": \)\"\"\([^\"]*\)\"/\1\"'\2'/g" $ToxDB_out >> ${ToxDB_out}.js
	printf "\n]" >>${ToxDB_out}.js

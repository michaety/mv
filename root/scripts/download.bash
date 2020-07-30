#!/usr/bin/with-contenv bash
agent="automated-music-video-downloader ( https://github.com/RandomNinjaAtk/docker-amvd )"
Configuration () {
	processstartid="$(ps -A -o pid,cmd|grep "/config/scripts/start.bash" | grep -v grep | head -n 1 | awk '{print $1}')"
	processdownloadid="$(ps -A -o pid,cmd|grep "/config/scripts/download.bash" | grep -v grep | head -n 1 | awk '{print $1}')"
	echo "To kill script, use the following command:"
	echo "kill -9 $processstartid"
	echo "kill -9 $processdownloadid"
	echo ""
	echo ""
	sleep 5

	echo "######################################### CONFIGURATION VERIFICATION #########################################"
	error=0
	
	# Verify Musicbrainz DB Connectivity
	musicbrainzdbtest=$(curl -s -A "$agent" "${MBRAINZMIRROR}/ws/2/artist/f59c5520-5f46-4d2c-b2c4-822eabf53419?fmt=json")
	musicbrainzdbtestname=$(echo "${musicbrainzdbtest}"| jq -r '.name')
	if [ "$musicbrainzdbtestname" != "Linkin Park" ]; then
		echo "ERROR: Cannot communicate with Musicbrainz"
		echo "ERROR: Expected Response \"Linkin Park\", received response \"$musicbrainzdbtestname\""
		echo "ERROR: URL might be Invalid: $MBRAINZMIRROR"
		echo "ERROR: Remote Mirror may be throttling connection..."
		echo "ERROR: Link used for testing: ${MBRAINZMIRROR}/ws/2/artist/f59c5520-5f46-4d2c-b2c4-822eabf53419?fmt=json"
		echo "ERROR: Please correct error, consider using official Musicbrainz URL: https://musicbrainz.org"
		error=1
	else
		echo "Musicbrainz Mirror Valid: $MBRAINZMIRROR"
		if echo "$MBRAINZMIRROR" | grep -i "musicbrainz.org" | read; then
			if [ "$MBRATELIMIT" != 1 ]; then
				MBRATELIMIT="1"
			fi
			echo "Musicbrainz Rate Limit: $MBRATELIMIT (Queries Per Second)"
		else
			echo "Musicbrainz Rate Limit: $MBRATELIMIT (Queries Per Second)"
			MBRATELIMIT="0$(echo $(( 100 * 1 / $MBRATELIMIT )) | sed 's/..$/.&/')"
		fi
	fi

	# verify LIBRARY
	if [ ! -z "$LIBRARY" ]; then
		echo "Video: Download Path: $LIBRARY"
	else
		echo "ERROR: LIBRARY setting invalid, currently set to: $LIBRARY"
		echo "ERROR: LIBRARY Expected Valid Setting: /your/path/to/music/video/folder"
		error=1
	fi
	if [ ! -d "$LIBRARY" ]; then			
		echo "ERROR: LIBRARY setting invalid, currently set to: $LIBRARY"
		echo "ERROR: The LIBRARY Folder does not exist, create the folder accordingly to resolve error"
		echo "HINT: Check the path using the container CLI to verify it exists, command: ls \"$LIBRARY\""
		error=1
	fi

	# Country Code
	if [ ! -z "$CountryCode" ]; then
		echo "Video: Country Code: $CountryCode"
	else
		echo "ERROR: CountryCode is empty, please configure wtih a valid Country Code (lowercase)"
		error=1
	fi

	# RequireVideoMatch
	if [ "$RequireVideoMatch" = "true" ]; then
		echo "Video: Require Video Match: ENABLED"
	else
		echo "Video: Require Video Match: DISABLED"
	fi
		
	# videoformat
	if [ ! -z "$videoformat" ]; then
		echo "Video: Format Set To: $videoformat"
	else
		echo "Video: Format Set To: --format bestvideo[vcodec*=avc1]+bestaudio[ext=m4a]"
	fi
		
	# videofilter
	if [ ! -z "$videofilter" ]; then
		echo "Video: Filter: ENABLED ($videofilter)"
	else
		echo "Video: Filter: DISABLED"
	fi
		
	# subtitlelanguage
	if [ ! -z "$subtitlelanguage" ]; then
		subtitlelanguage="${subtitlelanguage,,}"
		echo "Video: Subtitle Language: $subtitlelanguage"
	else
		subtitlelanguage="en"
		echo "Video: Subtitle Language: $subtitlelanguage"
	fi

	if [ $error = 1 ]; then
		echo "Please correct errors before attempting to run script again..."
		echo "Exiting..."
		exit 1
	fi
	sleep 5
}

CacheEngine () {
	echo "######################################### STARTING CACHE ENGINE #########################################"
	wantit=$(curl -s --header "X-Api-Key:"${LidarrAPIkey} --request GET  "$LidarrUrl/api/v1/Artist/")
	wantedtotal=$(echo "${wantit}"| jq -r '.[].sortName' | wc -l)
	MBArtistID=($(echo "${wantit}" | jq -r ".[].foreignArtistId"))

	if [ -d "/config/temp" ]; then
		rm -rf "/config/temp"
	fi
	for id in ${!MBArtistID[@]}; do
        artistnumber=$(( $id + 1 ))
		mbid="${MBArtistID[$id]}"
        LidArtistNameCap="$(echo "${wantit}" | jq -r ".[] | select(.foreignArtistId==\"${mbid}\") | .artistName")"
        sanatizedartistname="$(echo "${LidArtistNameCap}" | sed -e 's/[\\/:\*\?"<>\|\x01-\x1F\x7F]//g' -e 's/^\(nul\|prn\|con\|lpt[0-9]\|com[0-9]\|aux\)\(\.\|$\)//i' -e 's/^\.*$//' -e 's/^$/NONAME/')"

		if [ -f "/config/cache/$sanatizedartistname-$mbid-cache-complete" ]; then
			if ! [[ $(find "/config/cache/$sanatizedartistname-$mbid-cache-complete" -mtime +7 -print) ]]; then
				echo "${artistnumber} of ${wantedtotal} :: MBZDB CACHE :: $LidArtistNameCap :: Skipping until cache expires..."
				continue
			fi
		fi

        mbrainzurlcount=$(curl -s -A "$agent" "${MBRAINZMIRROR}/ws/2/artist/$mbid?inc=url-rels&fmt=json" | jq -r ".relations | .[] | .url | .resource" | wc -l)
	
		if [ -f "/config/cache/$sanatizedartistname-$mbid-info.json" ]; then
			cachedurlcount=$(cat "/config/cache/$sanatizedartistname-$mbid-info.json" | jq -r ".relations | .[] | .url | .resource" | wc -l)
			if [ "$mbrainzurlcount" -ne "$cachedurlcount" ]; then
				rm "/config/cache/$sanatizedartistname-$mbid-info.json"
			fi
		fi

		if [ ! -f "/config/cache/$sanatizedartistname-$mbid-info.json" ]; then
			echo "${artistnumber} of ${wantedtotal} :: MBZDB CACHE :: $LidArtistNameCap :: Caching Musicbrainz Artist Info..."
			curl -s -A "$agent" "${MBRAINZMIRROR}/ws/2/artist/$mbid?inc=url-rels+genres&fmt=json" -o "/config/cache/$sanatizedartistname-$mbid-info.json"
			sleep $MBRATELIMIT
		else 
			echo "${artistnumber} of ${wantedtotal} :: MBZDB CACHE :: $LidArtistNameCap :: Musicbrainz Artist Info Cache Valid..."
		fi
		
		records=$(curl -s -A "$agent" "${MBRAINZMIRROR}/ws/2/recording?artist=$mbid&limit=1&offset=0&fmt=json")
		sleep $MBRATELIMIT
		
		
		newrecordingcount=$(echo "${records}"| jq -r '."recording-count"')

				
		if [ ! -f "/config/cache/$sanatizedartistname-$mbid-recording-count.json" ]; then
			curl -s -A "$agent" "${MBRAINZMIRROR}/ws/2/recording?artist=$mbid&limit=1&offset=0&fmt=json" -o "/config/cache/$sanatizedartistname-$mbid-recording-count.json"
			sleep $MBRATELIMIT
		fi

		recordingcount=$(cat "/config/cache/$sanatizedartistname-$mbid-recording-count.json" | jq -r '."recording-count"')

		if [ $newrecordingcount != $recordingcount ]; then
			echo "$artistnumber of $wantedtotal :: MBZDB CACHE :: $LidArtistNameCap :: Cache needs update, cleaning..."
		
			if [ -f "/config/cache/$sanatizedartistname-$mbid-recordings.json" ]; then
				rm "/config/cache/$sanatizedartistname-$mbid-recordings.json"
			fi
		
			if [ -f "/config/cache/$sanatizedartistname-$mbid-recording-count.json" ]; then
				rm "/config/cache/$sanatizedartistname-$mbid-recording-count.json"
			fi
		
			if [ -f "/config/cache/$sanatizedartistname-$mbid-video-recordings.json" ]; then
				rm "/config/cache/$sanatizedartistname-$mbid-video-recordings.json"
			fi
		
			if [ ! -f "/config/cache/$sanatizedartistname-$mbid-recording-count.json" ]; then
				curl -s -A "$agent" "${MBRAINZMIRROR}/ws/2/recording?artist=$mbid&limit=1&offset=0&fmt=json" -o "/config/cache/$sanatizedartistname-$mbid-recording-count.json"
				sleep $MBRATELIMIT
			fi
		else
			if [ ! -f "/config/cache/$sanatizedartistname-$mbid-recordings.json" ]; then
				echo "$artistnumber of $wantedtotal :: MBZDB CACHE :: $LidArtistNameCap :: Caching MBZDB $recordingcount Recordings..."
			else
				echo "$artistnumber of $wantedtotal :: MBZDB CACHE :: $LidArtistNameCap :: MBZDB Recording Cache Is Valid..."
			fi
		fi

		if [ ! -f "/config/cache/$sanatizedartistname-$mbid-recordings.json" ]; then
			if [ ! -d "/config/temp" ]; then
				mkdir "/config/temp"
				sleep 0.1
			fi	
		
			offsetcount=$(( $recordingcount / 100 ))
			for ((i=0;i<=$offsetcount;i++)); do
				if [ ! -f "recording-page-$i.json" ]; then
					if [ $i != 0 ]; then
						offset=$(( $i * 100 ))
						dlnumber=$(( $offset + 100))
					else
						offset=0
						dlnumber=$(( $offset + 100))
					fi
	
					echo "$artistnumber of $wantedtotal :: MBZDB CACHE :: $LidArtistNameCap :: Downloading page $i... ($offset - $dlnumber Results)"
					curl -s -A "$agent" "${MBRAINZMIRROR}/ws/2/recording?artist=$mbid&inc=url-rels&limit=100&offset=$offset&fmt=json" -o "/config/temp/$mbid-recording-page-$i.json"
					sleep $MBRATELIMIT
				fi
			done

			if [ ! -f "/config/cache/$sanatizedartistname-recordings.json" ]; then
				jq -s '.' /config/temp/$mbid-recording-page-*.json > "/config/cache/$sanatizedartistname-$mbid-recordings.json"
			fi

			if [ -f "/config/cache/$sanatizedartistname-$mbid-recordings.json" ]; then
				rm /config/temp/$mbid-recording-page-*.json
				sleep .01
			fi

			if [ -d "/config/temp" ]; then
				sleep 0.1
				rm -rf "/config/temp"
			fi
		fi

		releases=$(curl -s -A "$agent" "${MBRAINZMIRROR}/ws/2/release?artist=$mbid&inc=genres+recordings+url-rels+release-groups&limit=1&offset=0&fmt=json")
		sleep $MBRATELIMIT
		newreleasecount=$(echo "${releases}"| jq -r '."release-count"')
				
		if [ ! -f "/config/cache/$sanatizedartistname-$mbid-releases.json" ]; then
			releasecount=$(echo "${releases}"| jq -r '."release-count"')
		else
			releasecount=$(cat "/config/cache/$sanatizedartistname-$mbid-releases.json" | jq -r '.[] | ."release-count"' | head -n 1)
		fi
			
		if [ $newreleasecount != $releasecount ]; then
			echo "$artistnumber of $wantedtotal :: MBZDB CACHE :: $LidArtistNameCap :: Cache needs update, cleaning..."
			if [ -f "/config/cache/$sanatizedartistname-$mbid-releases.json" ]; then
				rm "/config/cache/$sanatizedartistname-$mbid-releases.json"
			fi
		fi

		if [ ! -f "/config/cache/$sanatizedartistname-$mbid-releases.json" ]; then
			echo "$artistnumber of $wantedtotal :: MBZDB CACHE :: $LidArtistNameCap :: Caching $releasecount releases..."
		else
			echo "$artistnumber of $wantedtotal :: MBZDB CACHE :: $LidArtistNameCap :: Releases Cache Is Valid..."
		fi

		if [ ! -f "/config/cache/$sanatizedartistname-$mbid-releases.json" ]; then
			if [ ! -d "/config/temp" ]; then
				mkdir "/config/temp"
				sleep 0.1
			fi	
	
			offsetcount=$(( $releasecount / 100 ))
			for ((i=0;i<=$offsetcount;i++)); do
				if [ ! -f "release-page-$i.json" ]; then
					if [ $i != 0 ]; then
						offset=$(( $i * 100 ))
						dlnumber=$(( $offset + 100))
					else
						offset=0
						dlnumber=$(( $offset + 100))
					fi
					echo "$artistnumber of $wantedtotal :: MBZDB CACHE :: $LidArtistNameCap :: Downloading Releases page $i... ($offset - $dlnumber Results)"
					curl -s -A "$agent" "${MBRAINZMIRROR}/ws/2/release?artist=$mbid&inc=genres+recordings+url-rels+release-groups&limit=100&offset=$offset&fmt=json" -o "/config/temp/$mbid-releases-page-$i.json"
					sleep $MBRATELIMIT
				fi
			done


			if [ ! -f "/config/cache/$sanatizedartistname-releases.json" ]; then
				jq -s '.' /config/temp/$mbid-releases-page-*.json > "/config/cache/$sanatizedartistname-$mbid-releases.json"
			fi

			if [ -f "/config/cache/$sanatizedartistname-$mbid-releases.json" ]; then
				rm /config/temp/$mbid-releases-page-*.json
				sleep .01
			fi

			if [ -d "/config/temp" ]; then
				sleep 0.1
				rm -rf "/config/temp"
			fi
		fi
			
		mbzartistinfo="$(cat "/config/cache/$sanatizedartistname-$mbid-info.json")"
		imvdburl="$(echo "$mbzartistinfo" | jq -r ".relations | .[] | .url | select(.resource | contains(\"imvdb\")) | .resource")"
		if [ ! -z "$imvdburl" ]; then
			
			imvdbslug="$(basename "$imvdburl")"
			imvdbarurlfile="$(curl -s "https://imvdb.com/n/$imvdbslug")"
			imvdbarurllist=($(echo "$imvdbarurlfile" | grep -Eoi '<a [^>]+>' |  grep -Eo 'href="[^\"]+"' | grep -Eo '(http|https)://[^"]+' |  grep -i ".com/video" | grep -i "$imvdbslug" | sort -u))
			imvdbarurllistcount=$(echo "$imvdbarurlfile" | grep -Eoi '<a [^>]+>' |  grep -Eo 'href="[^\"]+"' | grep -Eo '(http|https)://[^"]+' |  grep -i ".com/video" | grep -i "$imvdbslug" | sort -u | wc -l)

			if [ -f "/config/cache/$sanatizedartistname-$mbid-imvdb.json" ]; then
				cachedimvdbcount="$(cat "/config/cache/$sanatizedartistname-$mbid-imvdb.json" | jq -r '.[] | .id' | wc -l)"
			else
				cachedimvdbcount="0"
			fi

			# echo "$imvdbarurllistcount -ne $cachedimvdbcount"

			if [ $imvdbarurllistcount -ne $cachedimvdbcount ]; then
				echo "$artistnumber of $wantedtotal :: IMVDB CACHE :: $LidArtistNameCap :: Cache out of date"
				if [ -f "/config/cache/$sanatizedartistname-$mbid-imvdb.json" ]; then
					rm "/config/cache/$sanatizedartistname-$mbid-imvdb.json"
				fi
			else
				echo "$artistnumber of $wantedtotal :: IMVDB CACHE :: $LidArtistNameCap :: Cache Valid"
			fi

			if [ ! -f "/config/cache/$sanatizedartistname-$mbid-imvdb.json" ]; then
				echo "$artistnumber of $wantedtotal :: IMVDB CACHE :: $LidArtistNameCap :: Caching Releases"
				if [ ! -d "/config/temp" ]; then
					mkdir "/config/temp"
					sleep 0.1
				fi
				for id in ${!imvdbarurllist[@]}; do
					urlnumber=$(( $id + 1 ))
					url="${imvdbarurllist[$id]}"
					imvdbvideoid=$(curl -s "$url" | grep -Eoi '<a [^>]+>' |  grep -Eo 'href="[^\"]+"' | grep -Eo '(http|https)://[^"]+' | grep "sandbox" | sed 's/^.*%2F//')
					echo "$artistnumber of $wantedtotal :: IMVDB CACHE :: $LidArtistNameCap :: Downloading Release $urlnumber Info"
					curl -s "https://imvdb.com/api/v1/video/$imvdbvideoid?include=sources" -o "/config/temp/$mbid-imvdb-$urlnumber.json"
				done
				if [ ! -f "/config/cache/$sanatizedartistname-$mbid-imvdb.json" ]; then
					jq -s '.' /config/temp//$mbid-imvdb-*.json > "/config/cache/$sanatizedartistname-$mbid-imvdb.json"
				fi
				if [ -f "/config/cache/$sanatizedartistname-$mbid-imvdb.json" ]; then
					echo "$artistnumber of $wantedtotal :: IMVDB CACHE :: $LidArtistNameCap :: Caching Complete"
				fi
				if [ -d "/config/temp" ]; then
					sleep 0.1
					rm -rf "/config/temp"
				fi
			fi
		fi
		touch "/config/cache/$sanatizedartistname-$mbid-cache-complete"
    done
}

DownloadVideos () {
	echo "######################################### DOWNLOADING VIDEOS #########################################"
	wantit=$(curl -s --header "X-Api-Key:"${LidarrAPIkey} --request GET  "$LidarrUrl/api/v1/Artist/")
	wantedtotal=$(echo "${wantit}"|jq -r '.[].sortName' | wc -l)
	MBArtistID=($(echo "${wantit}" | jq -r ".[].foreignArtistId"))
	CountryCodelowercase="$(echo ${CountryCode,,})"

	if [ -f "/config/cookies/cookies.txt" ]; then
		cookies="--cookies /config/cookies/cookies.txt"
	else
		cookies=""
	fi

	if [ -z "$videoformat" ]; then
		videoformat="--format bestvideo[vcodec*=avc1]+bestaudio[ext=m4a]"
	fi

	if [ -z "$videofilter" ]; then
		videofilter=""
	fi

	for id in ${!MBArtistID[@]}; do
		artistnumber=$(( $id + 1 ))
		mbid="${MBArtistID[$id]}"



		LidArtistPath="$(echo "${wantit}" | jq -r ".[] | select(.foreignArtistId==\"${mbid}\") | .path")"
		LidArtistNameCap="$(echo "${wantit}" | jq -r ".[] | select(.foreignArtistId==\"${mbid}\") | .artistName")"
		sanatizedartistname="$(echo "${LidArtistNameCap}" | sed -e 's/[\\/:\*\?"<>\|\x01-\x1F\x7F]//g' -e 's/^\(nul\|prn\|con\|lpt[0-9]\|com[0-9]\|aux\)\(\.\|$\)//i' -e 's/^\.*$//' -e 's/^$/NONAME/')"
		recordingsfile="$(cat "/config/cache/$sanatizedartistname-$mbid-recordings.json")"
		mbzartistinfo="$(cat "/config/cache/$sanatizedartistname-$mbid-info.json")"
		releasesfile="$(cat "/config/cache/$sanatizedartistname-$mbid-releases.json")"
		

		if [ -f "/config/cache/$sanatizedartistname-$mbid-download-complete" ]; then
			if ! [[ $(find "/config/cache/$sanatizedartistname-$mbid-download-complete" -mtime +7 -print) ]]; then
				echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: Artist already processed previously, skipping until cache expires..."
				continue
			fi
		fi

		echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: Processing"
		echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: Normalizing MBZDB Release Info (Capitalization)"
		releasesfilelowercase="$(echo ${releasesfile,,})"
		imvdburl="$(echo "$mbzartistinfo" | jq -r ".relations[] | .url | select(.resource | contains(\"imvdb\")) | .resource")"
		imvdbslug="$(basename "$imvdburl")"

		if [ -f "/config/cache/$sanatizedartistname-$mbid-imvdb.json" ]; then
			db="IMVDb"
			echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: IMVDB :: Aritst Link Found, using it's database for videos..."
			imvdbcache="$(cat "/config/cache/$sanatizedartistname-$mbid-imvdb.json")"
			imvdbids=($(echo "$imvdbcache" |  jq -r ".[] | select(.sources[] | select(.source==\"youtube\")) | .id"))
			videocount="$(echo "$imvdbcache" | jq -r ".[] | select(.sources[] | select(.source==\"youtube\")) | .id" | wc -l)"
			for id in ${!imvdbids[@]}; do
				currentprocess=$(( $id + 1 ))
				imvdbid="${imvdbids[$id]}"
				imvdbvideodata="$(echo "$imvdbcache" | jq -r ".[] | select(.id==$imvdbid) | .")"
				videotitle="$(echo "$imvdbvideodata" | jq -r ".song_title")"
				videodisambiguation=""
				videotitlelowercase="${videotitle,,}"
				videodirectors="$(echo "$imvdbvideodata" | jq -r ".directors[] | .entity_name")"
				videoyear="$(echo "$imvdbvideodata" | jq -r ".year")"
				santizevideotitle="$(echo "$imvdbvideotitle" | sed -e 's/[\\/:\*\?"<>\|\x01-\x1F\x7F]//g' -e 's/^\(nul\|prn\|con\|lpt[0-9]\|com[0-9]\|aux\)\(\.\|$\)//i' -e 's/^\.*$//' -e 's/^$/NONAME/')"
				youtubeid="$(echo "$imvdbvideodata" | jq -r ".sources[] | select(.source==\"youtube\") | .source_data" | head -n 1)"
				youtubeurl="https://www.youtube.com/watch?v=$youtubeid"
				if ! [ -f "/config/logs/download.log" ]; then
					touch "/config/logs/download.log"
				fi
				if cat "/config/logs/download.log" | grep -i ":: $youtubeid ::" | read; then
					echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: DOWNLOAD :: ${videotitle}${nfovideodisambiguation} :: Already downloaded... (see: /config/logs/download.log)"
					continue
				fi
				if cat "/config/logs/download.log" | grep -i "$youtubeurl" | read; then
					echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: DOWNLOAD :: ${videotitle}${nfovideodisambiguation} :: Already downloaded... (see: /config/logs/download.log)"
					continue
				fi

				youtubedata="$(python3 /usr/local/bin/youtube-dl ${cookies} -j $youtubeurl 2> /dev/null)"
				if [ -z "$youtubedata" ]; then
					continue
				fi
				youtubeuploaddate="$(echo "$youtubedata" | jq -r '.upload_date')"
				if [ "$imvdbvideoyear" = "null" ]; then 
					videoyear="$(echo ${youtubeuploaddate:0:4})"
				fi
				youtubeaveragerating="$(echo "$youtubedata" | jq -r '.average_rating')"
				videoalbum="$(echo "$youtubedata" | jq -r '.album')"
				sanatizedvideodisambiguation=""
				echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: MBZDB MATCH :: ${videotitle}${nfovideodisambiguation} :: Checking for match"

				VideoMatch

				if [ "$trackmatch" = "false" ]; then
					echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: MBZDB MATCH :: ERROR :: ${videotitle}${nfovideodisambiguation} :: Could not be matched to Musicbrainz"
					if [ "$RequireVideoMatch" = "true" ]; then
						echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: MBZDB MATCH :: ERROR :: ${videotitle}${nfovideodisambiguation} :: Require Match Enabled, skipping..."
						continue
					fi
				fi

				VideoDownload

				VideoNFOWriter

			done
		else
			if ! [ -f "imvdberror.log" ]; then
				touch "imvdberror.log"
			fi
			if [ -f "imvdberror.log" ]; then
				echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: MBZDB :: ERROR :: musicbrainz id: $mbid is missing IMVDB link, see: \"/config/logs/imvdberror.log\" for more detail..."
				if cat "/config/logs/imvdberror.log" | grep "$mbid" | read; then
					sleep 0.1
				else
					echo "Update Musicbrainz Relationship Page: https://musicbrainz.org/artist/$mbid/relationships for \"${LidArtistNameCap}\" with IMVDB Artist Link" >> "/config/logs/imvdberror.log"
				fi
			fi
		fi

		db="MBZDB"

		recordingcount=$(cat "/config/cache/$sanatizedartistname-$mbid-recording-count.json" | jq -r '."recording-count"')
			
		echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $recordingcount recordings found..."

		videorecordings=($(echo "$recordingsfile" | jq -r '.[] | .recordings | .[] | select(.video==true) | .id'))
		videocount=$(echo "$recordingsfile" | jq -r '.[] | .recordings | .[] | select(.video==true) | .id' | wc -l)
		echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: Checking $recordingcount recordings for videos..."
		echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $videocount video recordings found..."

		if [ $videocount = 0 ]; then
			echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: Skipping..."
			if [ ! -z "$imvdburl" ]; then
				downloadcount=$(find "$LIBRARY" -mindepth 1 -maxdepth 1 -type f -iname "$sanatizedartistname - *.mp4" | wc -l)
				echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $downloadcount Videos Downloaded!"
				echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: MARKING ARTIST AS COMPLETE"
				touch "/config/cache/$sanatizedartistname-$mbid-download-complete"
			fi
			continue
		fi

		echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: Checking $videocount video recordings for links..."
		videorecordsfile="$(echo "$recordingsfile" | jq -r '.[] | .recordings | .[] | select(.video==true) | .')"
		videocount="$(echo "$videorecordsfile" | jq -r 'select(.relations | .[] | .url | .resource | contains("youtube")) | .id' | sort -u | wc -l)"
		videorecordsid=($(echo "$videorecordsfile" | jq -r 'select(.relations | .[] | .url | .resource | contains("youtube")) | .id' | sort -u))
		echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $videocount video recordings with links found!"
		if [ $videocount = 0 ]; then
			echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: Skipping..."
			if [ ! -z "$imvdburl" ]; then
				downloadcount=$(find "$LIBRARY" -mindepth 1 -maxdepth 1 -type f -iname "$sanatizedartistname - *.mp4" | wc -l)
				echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $downloadcount Videos Downloaded!"
				echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: MARKING ARTIST AS COMPLETE"
				touch "/config/cache/$sanatizedartistname-$mbid-download-complete"
			fi
			continue
		fi
		
		echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: Processing $videocount video recordings..."
		for id in ${!videorecordsid[@]}; do
			currentprocess=$(( $id + 1 ))
			mbrecordid="${videorecordsid[$id]}"
			videotitle="$(echo "$videorecordsfile" | jq -r "select(.id==\"$mbrecordid\") | .title")"
			videotitlelowercase="$(echo ${videotitle,,})"
			videodisambiguation="$(echo "$videorecordsfile" | jq -r "select(.id==\"$mbrecordid\") | .disambiguation")"
			dlurl=($(echo "$videorecordsfile" | jq -r "select(.id==\"$mbrecordid\") | .relations | .[] | .url | .resource" | sort -u))
			sanitizevideotitle="$(echo "${videotitle}" | sed -e 's/[\\/:\*\?"<>\|\x01-\x1F\x7F]//g' -e 's/^\(nul\|prn\|con\|lpt[0-9]\|com[0-9]\|aux\)\(\.\|$\)//i' -e 's/^\.*$//' -e 's/^$/NONAME/')"
			sanitizedvideodisambiguation="$(echo "${videodisambiguation}" | sed -e 's/[\\/:\*\?"<>\|\x01-\x1F\x7F]//g' -e 's/^\(nul\|prn\|con\|lpt[0-9]\|com[0-9]\|aux\)\(\.\|$\)//i' -e 's/^\.*$//' -e 's/^$/NONAME/')"
			if ! [ -f "/config/logs/download.log" ]; then
				touch "/config/logs/download.log"
			fi
			if cat "/config/logs/download.log" | grep -i ".* :: ${mbrecordid} :: .*" | read; then
				echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: DOWNLOAD :: ${videotitle}${nfovideodisambiguation} :: Already downloaded... (see: /config/logs/download.log)"
				continue
			fi
			
			for url in ${!dlurl[@]}; do
				recordurl="${dlurl[$url]}"
				if echo "$recordurl" | grep -i "youtube" | read; then
					sleep 0.1
				else
					continue
				fi
				if cat "/config/logs/download.log" | grep -i "$recordurl" | read; then
					echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: DOWNLOAD :: ${videotitle}${nfovideodisambiguation} :: Already downloaded... (see: /config/logs/download.log)"
					break
				fi
				youtubedata="$(python3 /usr/local/bin/youtube-dl ${cookies} -j $recordurl 2> /dev/null)"
				if [ -z "$youtubedata" ]; then
					continue
				fi
				youtubeuploaddate="$(echo "$youtubedata" | jq -r '.upload_date')"
				videoyear="$(echo ${youtubeuploaddate:0:4})"
				youtubeaveragerating="$(echo "$youtubedata" | jq -r '.average_rating')"
				videoalbum="$(echo "$youtubedata" | jq -r '.album')"
				youtubeid="$(echo "$youtubedata" | jq -r '.id')"
				youtubeurl="https://www.youtube.com/watch?v=$youtubeid"
				if [ -z "$youtubeid" ]; then
					continue
				fi
				if cat "/config/logs/download.log" | grep -i ":: $youtubeid ::" | read; then
					echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: DOWNLOAD :: ${videotitle}${nfovideodisambiguation} :: Already downloaded... (see: /config/logs/download.log)"
					break
				fi
				if cat "/config/logs/download.log" | grep -i "$youtubeurl" | read; then
					echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: DOWNLOAD :: ${videotitle}${nfovideodisambiguation} :: Already downloaded... (see: /config/logs/download.log)"
					break
				fi
				
				echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: MBZDB MATCH :: ${videotitle}${nfovideodisambiguation} :: Checking for match"

				VideoMatch

				if [ "$trackmatch" = "false" ]; then
					if [ "$filter" = "true" ]; then
						echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: MBZDB MATCH :: ERROR :: ${videotitle}${nfovideodisambiguation} :: Not matched because of unwanted filter \"$videofilter\""
					else
						echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: MBZDB MATCH :: ERROR :: ${videotitle}${nfovideodisambiguation} :: Could not be matched to Musicbrainz"
					fi
					if [ "$RequireVideoMatch" = "true" ]; then
						echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: MBZDB MATCH :: ERROR :: ${videotitle}${nfovideodisambiguation} :: Require Match Enabled, skipping..."
						continue
					fi
				fi


				VideoDownload

				VideoNFOWriter

			done
		done
		downloadcount=$(find "$LIBRARY" -mindepth 1 -maxdepth 1 -type f -iname "$sanatizedartistname - *.mp4" | wc -l)
		echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $downloadcount Videos Downloaded!"
		echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: MARKING ARTIST AS COMPLETE"
		touch "/config/cache/$sanatizedartistname-$mbid-download-complete"
	done
	totaldownloadcount=$(find "$LIBRARY" -mindepth 1 -maxdepth 1 -type f -iname "*.mp4" | wc -l)
	echo "######################################### $totaldownloadcount VIDEOS DOWNLOADED #########################################"
}

VideoNFOWriter () {

	if [ -f "$LIBRARY/$sanatizedartistname - ${sanitizevideotitle}${sanitizedvideodisambiguation}.mp4" ]; then
		if [ ! -f "$LIBRARY/$sanatizedartistname - ${sanitizevideotitle}${sanitizedvideodisambiguation}.nfo" ]; then
			if [ "$videoyear" != "null" ]; then
				year="$videoyear"
			else
				year=""
			fi
			if [ "$videoalbum" != "null" ]; then
				album="$videoalbum"
			else
				album=""
			fi
			if [ -f "$LIBRARY/$sanatizedartistname - ${sanitizevideotitle}${sanitizedvideodisambiguation}.jpg" ]; then
				thumb="$sanatizedartistname - ${sanitizevideotitle}${sanitizedvideodisambiguation}.jpg"
			else
				thumb=""
			fi
			# Genre
			if [ ! -z "$videogenres" ]; then
				genres="$(echo "$videogenres" | sort -u)"
				OUT=""
				SAVEIFS=$IFS
				IFS=$(echo -en "\n\b")
				for f in $genres
				do
					OUT=$OUT"    <genre>$f</genre>\n"
				done
				IFS=$SAVEIFS
				genre="$(echo -e "$OUT")"
			fi

			if [ ! -z "$videodirectors" ]; then
				OUT=""
				SAVEIFS=$IFS
				IFS=$(echo -en "\n\b")
				for f in $videodirectors
				do
					OUT=$OUT"    <director>$f</director>\n"
				done
				IFS=$SAVEIFS
				director="$(echo -e "$OUT")"
			else
				director="    <director></director>"
			fi
			if [ "$trackmatch" = "true" ]; then
				track="$videotrackposition"
			else
				track=""
			fi
 			echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: NFO WRITER :: Writing NFO for ${videotitle}${nfovideodisambiguation}"
cat <<EOF > "$LIBRARY/$sanatizedartistname - ${sanitizevideotitle}${sanitizedvideodisambiguation}.nfo"
<musicvideo>
    <title>${videotitle}${nfovideodisambiguation}</title>
    <userrating>$youtubeaveragerating</userrating>
    <track>$track</track>
    <album>$album</album>
    <plot></plot>
$genre
$director
    <premiered></premiered>
    <year>$year</year>
    <studio></studio>
    <artist>$LidArtistNameCap</artist>
    <thumb>$thumb</thumb>
</musicvideo>
EOF
		fi
	fi

}

VideoMatch () {

	trackmatch="false"
	filter="false"
	skip="false"
	releaseid=""
	videotitlelowercase="$(echo $videotitlelowercase | sed 's/"/\\"/g')"
	# album match first...
	# Preferred Country
	if [ -z "$releaseid" ]; then
		releaseid=($(echo "$releasesfilelowercase" | jq -s -r ".[] | .[] | .releases | sort_by(.date) | .[] | select(.date!=\"\" and .country==\"$CountryCodelowercase\" and .status==\"official\") | select(.\"release-group\".\"primary-type\"==\"album\") | select(.media[] | .tracks[] | .title==\"$videotitlelowercase\") | .id"))
	fi

	# WorldWide
	if [ -z "$releaseid" ]; then
		releaseid=($(echo "$releasesfilelowercase" | jq -s -r ".[] | .[] | .releases | sort_by(.date) | .[] | select(.date!=\"\" and .country==\"xw\" and .status==\"official\") | select(.\"release-group\".\"primary-type\"==\"album\") | select(.media[] | .tracks[] | .title==\"$videotitlelowercase\") | .id"))
	fi

	# Everywhere
	if [ -z "$releaseid" ]; then
		releaseid=($(echo "$releasesfilelowercase" | jq -s -r ".[] | .[] | .releases | sort_by(.date) | .[] | select(.date!=\"\" and .status==\"official\") | select(.\"release-group\".\"primary-type\"==\"album\") | select(.media[] | .tracks[] | .title==\"$videotitlelowercase\") | .id"))
	fi

	# single match second...
	# Preferred Country
	if [ -z "$releaseid" ]; then
		releaseid=($(echo "$releasesfilelowercase" | jq -s -r ".[] | .[] | .releases | sort_by(.date) | .[] | select(.date!=\"\" and .country==\"$CountryCodelowercase\" and .status==\"official\") | select(.\"release-group\".\"primary-type\"==\"single\") | select(.media[] | .tracks[] | .title==\"$videotitlelowercase\") | .id"))
	fi

	# WorldWide
	if [ -z "$releaseid" ]; then
		releaseid=($(echo "$releasesfilelowercase" | jq -s -r ".[] | .[] | .releases | sort_by(.date) | .[] | select(.date!=\"\" and .country==\"xw\" and .status==\"official\") | select(.\"release-group\".\"primary-type\"==\"single\") | select(.media[] | .tracks[] | .title==\"$videotitlelowercase\") | .id"))
	fi

	# Everywhere
	if [ -z "$releaseid" ]; then
		releaseid=($(echo "$releasesfilelowercase" | jq -s -r ".[] | .[] | .releases | sort_by(.date) | .[] | select(.date!=\"\" and .status==\"official\") | select(.\"release-group\".\"primary-type\"==\"single\") | select(.media[] | .tracks[] | .title==\"$videotitlelowercase\") | .id"))
	fi

	# ep match third...
	# Preferred Country
	if [ -z "$releaseid" ]; then
		releaseid=($(echo "$releasesfilelowercase" | jq -s -r ".[] | .[] | .releases | sort_by(.date) | .[] | select(.date!=\"\" and .country==\"$CountryCodelowercase\" and .status==\"official\") | select(.\"release-group\".\"primary-type\"==\"ep\") | select(.media[] | .tracks[] | .title==\"$videotitlelowercase\") | .id"))
	fi

	# WorldWide
	if [ -z "$releaseid" ]; then
		releaseid=($(echo "$releasesfilelowercase" | jq -s -r ".[] | .[] | .releases | sort_by(.date) | .[] | select(.date!=\"\" and .country==\"xw\" and .status==\"official\") | select(.\"release-group\".\"primary-type\"==\"ep\") | select(.media[] | .tracks[] | .title==\"$videotitlelowercase\") | .id"))
	fi

	# Everywhere
	if [ -z "$releaseid" ]; then
		releaseid=($(echo "$releasesfilelowercase" | jq -s -r ".[] | .[] | .releases | sort_by(.date) | .[] | select(.date!=\"\" and .status==\"official\") | select(.\"release-group\".\"primary-type\"==\"ep\") | select(.media[] | .tracks[] | .title==\"$videotitlelowercase\") | .id"))
	fi

	# match any type fourth...
	# Preferred Country
	if [ -z "$releaseid" ]; then
		releaseid=($(echo "$releasesfilelowercase" | jq -s -r ".[] | .[] | .releases | sort_by(.date) | .[] | select(.date!=\"\" and .country==\"$CountryCodelowercase\" and .status==\"official\") | select(.media[] | .tracks[] | .title==\"$videotitlelowercase\") | .id"))
	fi

	# WorldWide
	if [ -z "$releaseid" ]; then
		releaseid=($(echo "$releasesfilelowercase" | jq -s -r ".[] | .[] | .releases | sort_by(.date) | .[] | select(.date!=\"\" and .country==\"xw\" and .status==\"official\") | select(.media[] | .tracks[] | .title==\"$videotitlelowercase\") | .id"))
	fi

	# Everywhere
	if [ -z "$releaseid" ]; then
		releaseid=($(echo "$releasesfilelowercase" | jq -s -r ".[] | .[] | .releases | sort_by(.date) | .[] | select(.date!=\"\" and .status==\"official\" ) | select(.media[] | .tracks[] | .title==\"$videotitlelowercase\") | .id"))
	fi

	# Loop through matched track releaseid's to find a corresponding release-group match
	if [ ! -z "$releaseid" ]; then
		for id in ${!releaseid[@]}; do
			subprocess=$(( $id + 1 ))
			trackreleaseid="${releaseid[$id]}"
			releasedata="$(echo "$releasesfile" | jq -r ".[] | .releases[] | select(.id==\"$trackreleaseid\")")"
			releasedatalowercase="$(echo ${releasedata,,})"
			releasetrackid="$(echo "$releasedatalowercase" | jq -r ".media[] | .tracks[] | select(.title==\"$videotitlelowercase\") | .id" | head -n 1)"
			releasetracktitle="$(echo "$releasedata" | jq -r ".media[] | .tracks[] | select(.id==\"$releasetrackid\") | .title" | head -n 1)"
			releasetrackposition="$(echo "$releasedata" | jq -r ".media[] | .tracks[] | select(.id==\"$releasetrackid\") | .position")"
			releasetitle="$(echo "$releasedata" | jq -r ".title")"
			releasestatus="$(echo "$releasedata" | jq -r ".status")"
			releasecountry="$(echo "$releasedata" | jq -r ".country")"
			releasegrouptitle="$(echo "$releasedata" | jq -r '."release-group"."title"')"
			releasegroupdate="$(echo "$releasedata" | jq -r '."release-group"."first-release-date"')"
			releasegroupyear="$(echo ${releasegroupdate:0:4})"
			releasegroupstatus="$(echo "$releasedata" | jq -r '."release-group" | ."primary-type"')"
			releasegroupsecondarytype="$(echo "$releasedata" | jq -r '."release-group" | ."secondary-types"[]')"
			releasegroupgenres="$(echo "$releasedata" | jq -r '."release-group" | .genres[] | .name' | sort -u)"

			# Skip null country
			if [ "$releasecountry" = null ]; then
				skip=true
			fi

			if [ ! -z "$videofilter" ]; then
				# Skip filter album matches
				if echo "$releasegroupsecondarytype" | grep -i "$videofilter" | read; then
					skip=true
					filter=true
				fi

				# Skip filter album matches
				if [ ! -z "$videodisambiguation" ]; then
					if echo "$videodisambiguation" | grep -i "$videofilter" | read; then
						skip=true
						filter=true
					fi
				fi
			fi

			# Use artist genres, if release group genres don't exist
			if [ -z "$releasegroupgenres" ]; then
				releasegroupgenres="$(echo "$mbzartistinfo" | jq -r '.genres[] | .name' | sort -u | sed -e "s/\b\(.\)/\u\1/g")"
			fi

			if [ "$skip" = false ]; then
				trackmatch=true
				filter=false
				echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: MBZDB MATCH :: Track $releasetrackposition :: $releasetracktitle :: $releasegrouptitle :: $releasestatus :: $releasecountry :: $releasegroupstatus :: $releasegroupyear"
				videotrackposition="$releasetrackposition"
				videotitle="$releasetracktitle"
				sanitizevideotitle="$(echo "$videotitle" | sed -e 's/[\\/:\*\?"<>\|\x01-\x1F\x7F]//g' -e 's/^\(nul\|prn\|con\|lpt[0-9]\|com[0-9]\|aux\)\(\.\|$\)//i' -e 's/^\.*$//' -e 's/^$/NONAME/')"
				videoyear="$releasegroupyear"
				videoalbum="$releasegrouptitle"
				videogenres="$(echo "$releasegroupgenres" | sed -e "s/\b\(.\)/\u\1/g")"
				break
			else
				trackmatch=false
				skip=false
				continue
			fi
		done
	fi
}

VideoDownload () {
	if [ ! -z "$videodisambiguation" ]; then
		nfovideodisambiguation=" ($videodisambiguation)"
		sanitizedvideodisambiguation=" ($(echo "${videodisambiguation}" | sed -e 's/[\\/:\*\?"<>\|\x01-\x1F\x7F]//g' -e 's/^\(nul\|prn\|con\|lpt[0-9]\|com[0-9]\|aux\)\(\.\|$\)//i' -e 's/^\.*$//' -e 's/^$/NONAME/'))"
	else
		nfovideodisambiguation=""
		sanitizedvideodisambiguation=""
	fi
	if [ "$videoyear" != "null" ]; then
		year="$videoyear"
	else
		year=""
	fi
	if [ "$videoalbum" != "null" ]; then
		album="$videoalbum"
	else
		album=""
	fi
	# Genre
	if [ ! -z "$videogenres" ]; then
		genres="$(echo "$videogenres" | sort -u)"
		OUT=""
		SAVEIFS=$IFS
		IFS=$(echo -en "\n\b")
		for f in $genres
		do
			OUT=$OUT"$f / "
		done
		IFS=$SAVEIFS
		genre="${OUT%???}"
	fi
	if [ "$trackmatch" = "true" ]; then
		track="$videotrackposition"
	else
		track=""
	fi
	if [ ! -f "$LIBRARY/$sanatizedartistname - ${sanitizevideotitle}${sanitizedvideodisambiguation}.mp4" ]; then
		if [ -f "$LIBRARY/$sanatizedartistname - ${sanitizevideotitle}${sanitizedvideodisambiguation}.mkv" ]; then
			rm "$LIBRARY/$sanatizedartistname - ${sanitizevideotitle}${sanitizedvideodisambiguation}".*
		fi
		echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: DOWNLOAD :: ${videotitle}${nfovideodisambiguation} :: Processing ($youtubeurl)... with youtube-dl"
		python3 /usr/local/bin/youtube-dl -v ${cookies} -o "$LIBRARY/$sanatizedartistname - ${sanitizevideotitle}${sanitizedvideodisambiguation}" ${videoformat} --write-sub --sub-lang $subtitlelanguage --embed-subs --merge-output-format mp4 --no-mtime --geo-bypass "$youtubeurl" &> /dev/nul
		if [ -f "$LIBRARY/$sanatizedartistname - ${sanitizevideotitle}${sanitizedvideodisambiguation}.mp4" ]; then
			echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: DOWNLOAD :: ${videotitle}${nfovideodisambiguation} :: Complete!"
			ffmpeg -y \
				-i "$LIBRARY/$sanatizedartistname - ${sanitizevideotitle}${sanitizedvideodisambiguation}.mp4" \
				-vframes 1 -an -s 640x360 -ss 30 \
				"$LIBRARY/$sanatizedartistname - ${sanitizevideotitle}${sanitizedvideodisambiguation}.jpg" &> /dev/null
			mv "$LIBRARY/$sanatizedartistname - ${sanitizevideotitle}${sanitizedvideodisambiguation}.mp4" "$LIBRARY/temp.mp4"
			ffmpeg -y \
				-i "$LIBRARY/temp.mp4" \
				-i "$LIBRARY/$sanatizedartistname - ${sanitizevideotitle}${sanitizedvideodisambiguation}.jpg" \
				-map 0 -map 1 -c copy -c:v:1 jpg -disposition:v:1 attached_pic \
				-c copy \
				-metadata title="${videotitle}${nfovideodisambiguation}" \
				-metadata artist="$LidArtistNameCap" \
				-metadata album_artist="$LidArtistNameCap" \
				-metadata album="$album" \
				-metadata date="$year" \
				-metadata genre="$genre" \
				-metadata track="$track" \
				-metadata media_type="6" \
				-movflags +faststart \
				"$LIBRARY/$sanatizedartistname - ${sanitizevideotitle}${sanitizedvideodisambiguation}.mp4" &> /dev/null
			rm "$LIBRARY/temp.mp4"
			echo "Video :: Downloaded :: $db :: ${LidArtistNameCap} :: $youtubeid :: $youtubeurl :: ${videotitle}${nfovideodisambiguation}" >> "/config/logs/download.log"
		else
			echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: DOWNLOAD :: ${videotitle}${nfovideodisambiguation} :: Downloaded Failed!"
		fi
	else
		echo "$artistnumber of $wantedtotal :: $LidArtistNameCap :: $db :: $currentprocess of $videocount :: DOWNLOAD :: ${videotitle}${nfovideodisambiguation} ::  ${videotitle}${nfovideodisambiguation} already downloaded!"
		if cat "/config/logs/download.log" | grep -i ":: $youtubeid ::" | read; then
			sleep 0.1
		else
			echo "Video :: Downloaded :: $db :: ${LidArtistNameCap} :: $youtubeid :: $youtubeurl :: ${videotitle}${nfovideodisambiguation}" >> "/config/logs/download.log"
		fi
	fi
}

Configuration
CacheEngine
DownloadVideos

exit 0
#!/bin/bash

# BI Alert
function bialert {
  if (( $BIALERTLAST < `date +%s` )); then
    # Remove old alert file
    rm -f alerts/$CAMERA.jpg

    # Copy alert image to BI
    cp $CAMERA.jpg alerts

    # Send alert to BI
    curl "http://$BISERVER/admin?trigger&camera=$CAMERA&user=$BIUSER&pw=$BIPW&memo=${CAPTION:${#CAMERA}+3}&jpeg=C:\\BlueIris\Alerts\\$CAMERA.jpg" > /dev/null 2>&1 &

    # Set next alert in epoch seconds
    BIALERTLAST=$(echo `date +%s`+$BIALERTCD | bc)
  fi
}

# Side Gate Lights Alert
function sglightsalert {
  if (( $SGLIGHTSALERTLAST < `date +%s` )); then
    curl http://"$HEIP"/apps/api/"$HEAPI"/devices/"$HESGLIGHTS"/on?access_token="$HETOKEN" > /dev/null 2>&1 &

    # Set next alert in epoch seconds
    SGLIGHTSALERTLAST=$(echo `date +%s`+$SGLIGHTSALERTCD | bc)
  fi
}


# Back Patio Lights Alert
function bplightsalert {
  if (( $BPLIGHTSALERTLAST < `date +%s` )); then
    curl http://"$HEIP"/apps/api/"$HEAPI"/devices/"$HEBPLIGHTS"/on?access_token="$HETOKEN" > /dev/null 2>&1 &

    # Set next alert in epoch seconds
    BPLIGHTSALERTLAST=$(echo `date +%s`+$BPLIGHTSALERTCD | bc)
  fi
}

# Driveway Lights Alert
function dwlightsalert {
  if (( $DWLIGHTSALERTLAST < `date +%s` )); then
    curl http://"$HEIP"/apps/api/"$HEAPI"/devices/"$HEDWLIGHTS"/on?access_token="$HETOKEN" > /dev/null 2>&1 &

    # Set next alert in epoch seconds
    DWLIGHTSALERTLAST=$(echo `date +%s`+$DWLIGHTSALERTCD | bc)
  fi
}

# Front Door Lights Alert
function fdlightsalert {
  if (( $FDLIGHTSALERTLAST < `date +%s` )); then
    curl http://"$HEIP"/apps/api/"$HEAPI"/devices/"$HEFDLIGHTS"/on?access_token="$HETOKEN" > /dev/null 2>&1 &

    # Set next alert in epoch seconds
    FDLIGHTSALERTLAST=$(echo `date +%s`+$FDLIGHTSALERTCD | bc)
  fi
}

# Flowerbed
function fblightsalert {
  if (( $FBLIGHTSALERTLAST < `date +%s` )); then
    curl http://"$HEIP"/apps/api/"$HEAPI"/devices/"$HEFBLIGHTS"/on?access_token="$HETOKEN" > /dev/null 2>&1 &

    # Set next alert in epoch seconds
    FBLIGHTSALERTLAST=$(echo `date +%s`+$FBLIGHTSALERTCD | bc)
  fi
}


# Telegram Alert
function telegramalert {
  if (( $TELEGRAMALERTLAST < `date +%s` )); then
  # Send camera alert to TG
  curl -F "caption=$CAPTION" -F "chat_id=$TGCID" -F "photo=@ramdrive/$CAMERA.jpg" https://api.telegram.org/bot"$TGBOT"/sendphoto > /dev/null 2>&1 &

  # Set next alert in epoch seconds
  TELEGRAMALERTLAST=$(echo `date +%s`+$TELEGRAMALERTCD | bc)
  fi
}

# Copy most resent alerts to web directory
function recent2www {
  rm -f /var/www/html/4"$CAMERA".jpg
  cp "$CAMERA".jpg /var/www/html/"$CAMERA".jpg
}

# Check if dection is different from last detection
function isdetectiondifferent {
  # If previous photo doesn't exist create a generic one
  if [ ! -f "ramdrive/$CAMERA"_p.bmp ]; then
    convert -size 100x100 xc:white "ramdrive/$CAMERA"_p.bmp
  fi

  # Get sameness decimal from last sent image
  PHOTODIFF=`compare -metric NCC "ramdrive/$CAMERA".bmp "ramdrive/$CAMERA"_p.bmp null: 2>&1`

  # Convert decimal of sameness to percent of differentness
  PHOTODIFF=$(echo 100-$PHOTODIFF*100 | bc)

  # Make it an int so bash doesn't loose its god damned mind
  PHOTODIFF=`printf "%.0f" "$PHOTODIFF"`

  # So... is it differenty enough?
  if (( $PHOTODIFF > $PERCENTDIFFERENT )); then
    # Remove old previous file
    rm -f "ramdrive/$CAMERA"_p.bmp

    # Copy current to new previous file
    cp "ramdrive/$CAMERA".bmp "ramdrive/$CAMERA"_p.bmp

    echo 1 # yes
  else
    echo 0 # no
  fi
}

# Hit up Deepstack AI for some sweet sweet skynet goodness
function detect {
  # Delete old image and get new one
  rm -f "ramdrive/$CAMERA".jpg
  rm -f "ramdrive/$CAMERA".bmp

  if [[ "$CAMERA" == "ipcamg1" ]] || [[ "$CAMERA" == "ipcamg2" ]] || [[ "$CAMERA" == "ipcamg3" ]] || [[ "$CAMERA" == "ipcamfd" ]] || [[ "$CAMERA" == "ipcamd1" ]] || [[ "$CAMERA" == "ipcamlv" ]] || [[ "$CAMERA" == "ipcambd" ]]; then
    wget "http://admin:dis9ter3@$CAMERA.me.pgnet.us/cgi-bin/snapshot.cgi" -O "ramdrive/$CAMERA".jpg > /dev/null 2>&1
  else
    wget "http://$BISERVER/image/$CAMERA?user=$BIUSER&pw=$BIPW&q=$BISSQ&s=$BISSS&decode=$BISID" -O "ramdrive/$CAMERA".jpg > /dev/null 2>&1
  fi

  # Convert to bmp and remove jpg
  convert -quiet "ramdrive/$CAMERA".jpg "ramdrive/$CAMERA".bmp
  rm -f "ramdrive/$CAMERA".jpg

  # Add mask if it exists
  if [ -f "conf/$CAMERA"_mask.txt ]; then
      convert -quality 100 "ramdrive/$CAMERA".bmp -fill black -draw @"conf/$CAMERA"_mask.txt "ramdrive/$CAMERA"_m.jpg
  else
      convert -quality 100 "ramdrive/$CAMERA".bmp "ramdrive/$CAMERA"_m.jpg
  fi

  # Delete old json and send masked image to Deepstack AI for detection
  rm -f "ramdrive/$CAMERA".json
  #curl -F image=@"ramdrive/$CAMERA"_m.jpg http://${DSAISERVERLIST[$DSAISERV]}/v1/vision/detection -o "ramdrive/$CAMERA".json > /dev/null 2>&1
  curl -F image=@"ramdrive/$CAMERA"_m.jpg http://${DSAISERVERLIST[$DSAISERV]}/v1/vision/custom/ipcam-combined -o "ramdrive/$CAMERA".json > /dev/null 2>&1

  # Get the number of found things
  THINGS=`jq '.predictions | length' "ramdrive/$CAMERA".json`

  # Set caption to camera name
  CAPTION=$CAMERA" - "

  # Iterate through each of the found things
  for (( i=0; i<$THINGS; i++ ))
  do
    # Get name of found thing 
    LABEL=`jq ".predictions[$i].label" "ramdrive/$CAMERA".json  | sed 's/"//g' | tr [:lower:] [:upper:]`

    # Iterate through THINGLIST
    for (( i2=0; i2<${#THINGLIST[@]}; i2=i2+2 ))
    do
      # Check if Found THING is something we want
      if [[ " ${THINGLIST[$i2]} " = " ${LABEL} " ]]; then
 
        # Get prediction confidence and mung it into an int
        CONFIDENCE=`jq ".predictions[$i].confidence" "ramdrive/$CAMERA".json`
        CONFIDENCE=${CONFIDENCE:2:2}
        
        # Check if found thing is high enough confidence
        if (( $CONFIDENCE > ${THINGLIST[$i2+1]} )); then
          # Add to caption
          CAPTION+=$LABEL" "$CONFIDENCE"% "

          # Get rectangle where found thing was found
          Y_MIN=`jq ".predictions[$i].y_min" "ramdrive/$CAMERA".json`
          X_MIN=`jq ".predictions[$i].x_min" "ramdrive/$CAMERA".json`
          Y_MAX=`jq ".predictions[$i].y_max" "ramdrive/$CAMERA".json`
          X_MAX=`jq ".predictions[$i].x_max" "ramdrive/$CAMERA".json`

          # Draw box around thing
          convert "ramdrive/$CAMERA".bmp -fill none -stroke red -strokewidth 1 -draw "rectangle $X_MIN,$Y_MIN $X_MAX,$Y_MAX" "ramdrive/$CAMERA".bmp

          # Figure out where the text will be and draw text background
          X_RECT=`convert -font helvetica -pointsize 18 label:"$LABEL $CONFIDENCE%" -format %w info:`
          X_RECT=$((X_MIN+X_RECT))
          Y_RECT=$((Y_MIN-16))
          convert "ramdrive/$CAMERA".bmp -fill red -stroke red -strokewidth 1 -draw "rectangle $X_MIN,$Y_MIN $X_RECT,$Y_RECT" "ramdrive/$CAMERA".bmp

          # Draw text
          convert "ramdrive/$CAMERA".bmp -font helvetica -pointsize 18 -draw "text $X_MIN,$Y_MIN '"$LABEL" "$CONFIDENCE"%'" "ramdrive/$CAMERA".bmp

          # Convert back to jpg
          convert -quality 100 "ramdrive/$CAMERA".bmp "ramdrive/$CAMERA".jpg

          # Alerts that fire on every detection
          # {
          if (( $BIALERT == 1 )); then
            # Send alert to BlueIris
            bialert
          fi

          if (( $FDLIGHTSALERT == 1 )); then
            # Front Door lights
            fdlightsalert
          fi

          if (( $FBLIGHTSALERT == 1 )); then
            # flowerbed lights
            fblightsalert
          fi

          if (( $DWLIGHTSALERT == 1 )); then
            # driveway lights
            dwlightsalert
          fi

          if (( $BPLIGHTSALERT == 1 )); then
            # back patio lights
            bplightsalert
          fi
          
          if (( $SGLIGHTSALERT == 1 )); then
            # side gate lights
            sglightsalert
          fi

          # Copy to web dir
          #recent2www
          # }

          # Alerts that only fire when current and last detection are differenty enough
          # {
          if [ "$(isdetectiondifferent)" -eq 1 ]; then
            if (( $TELEGRAMALERT == 1 )); then
              # Telegram
              telegramalert
            fi

#            if (( $FBLIGHTSALERT == 1 )); then
#              # flowerbed lights
#              fblightsalert
#            fi

#            if (( $DWLIGHTSALERT == 1 )); then
#              # front lights
#              frontlightsalert
#            fi
          fi
          # }

          # Now we sleep for a bit, since for the next (lowest of all CD timers) detections won't trigger anything anyways
          # This should probably be a few seconds lower than the lost of all CD timers.
          sleep $DETECTSLEEP
        fi
      fi
    done
  done
}

# Insert Vodka and press any key to continue
function loopy {
  # Set camera name
  CAMERA=$1

  # Load camera config
  . conf/$CAMERA.conf

  # Remove previous alert image
  rm -f "ramdrive/$CAMERA"_p.bmp
  # Prime alert timers
  TELEGRAMALERTLAST=0
  FBLIGHTSALERTLAST=0
  FDLIGHTSALERTLAST=0
  DWLIGHTSALERTLAST=0
  BPLIGHTSALERTLAST=0
  SGLIGHTSALERTLAST=0
  BIALERTLAST=0

  RINGCAMERAENABLED=0 #//default

  # Set some defaults
  THREADSLEEP=1
  PERCENTDIFFERENT=10
  TELEGRAMALERT=0
  TELEGRAMALERTCD=30
  FBLIGHTSALERT=0
  FBLIGHTSALERTCD=45
  FDLIGHTSALERT=0
  FDLIGHTSALERTCD=240
  DWLIGHTSALERT=0
  DWLIGHTSALERTCD=240
  BPLIGHTSALERT=0
  BPLIGHTSALERTCD=240
  SGLIGHTSALERT=0
  SGLIGHTSALERTCD=240
  BIALERT=1
  BIALERTCD=55


  # Find min CD timer
  DETECTSLEEP=TELEGRAMALERTCD
  if (( $DETECTSLEEP > $FBLIGHTSALERTCD )); then
    DETECTSLEEP=$FBLIGHTSALERTCD
  fi
  if (( $DETECTSLEEP > $DWLIGHTSALERTCD )); then
    DETECTSLEEP=$DWLIGHTSALERTCD
  fi
  if (( $DETECTSLEEP > $BIALERTCD )); then
    DETECTSLEEP=$BIALERTCD
  fi
  DETECTSLEEP=$((DETECTSLEEP-$THREADSLEEP-5))
  if (( $DETECTSLEEP < 5 )); then
    DETECTSLEEP=5
  fi
  
  # Startup with a random Deepstack AI endpoint
  DSAISERV=$((0 + $RANDOM % ${#DSAISERVERLIST[@]}))

  ## Do things until the heat death of the universe
  while [ 1 ]
  do
    # Run detect function
    detect

    # Choose next Deepstack AI endpoint
    DSAISERV=$((DSAISERV+1))

    # Loop to first Deepstack AI endpoint if necessary
    if (( $DSAISERV >= ${#DSAISERVERLIST[@]} )); then
      DSAISERV=0
    fi
  
    # Reload camera config after every loop so changes to config are automatically picked up
    . conf/$CAMERA.conf

    # Sleep some every loop
    sleep $THREADSLEEP
  done &
}

# Start camera threads for each camera config file found
for file in conf/*.conf; do
  filename=$(basename -- "$file")
  extension="${filename##*.}"
  filename="${filename%.*}"
  echo $filename
  loopy $filename #camera name
done

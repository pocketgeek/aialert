#!/bin/bash

# Do Things
function aialert {
  # Delete old image and get new one
  rm -f "$1".jpg
  rm -f "$1".bmp
  wget "http://$BISERVER/image/$1?user=$BIUSER&pw=$BIPW&q=$2&s=$3&decode=$4" -O "$1".jpg > /dev/null 2>&1

  # Convert to bmp
  convert "$1".jpg "$1".bmp

  # Add mask if it exists
  if [ -f "$1"_mask.txt ]; then
      convert "$1".bmp -fill black -draw @"$1"_mask.txt "$1"_m.jpg
  else
      convert "$1".bmp "$1"_m.jpg
  fi

  # Delete old json and send masked image to Deepstack AI for detection
  rm -f "$1".json
  curl -F image=@"$1"_m.jpg http://${DSAISERVERLIST[$DSAISERVNUM]}/v1/vision/detection -o "$1".json > /dev/null 2>&1

  # Get the number of found things
  THINGS=`jq '.predictions | length' "$1".json`

  # To send photo or not we don't yet know so 0
  SENDPHOTO=0

  # Set caption to camera name
  CAPTION=$1" - "

  # Iterate through each of the found things
  for (( i=0; i<$THINGS; i++ ))
  do
    # Get name of found thing 
    LABEL=`jq ".predictions[$i].label" "$1".json  | sed 's/"//g' | tr [:lower:] [:upper:]`

    # Iterate through THINGLIST
    for (( i2=0; i2<${#THINGLIST[@]}; i2=i2+2 ))
    do
      # Check if Found THING is something we want
      if [[ " ${THINGLIST[$i2]} " = " ${LABEL} " ]]; then
 
        # Get prediction confidence and mung it into an int
        CONF=`jq ".predictions[$i].confidence" "$1".json`
        CONF=${CONF:2:2}
        
        # Check if found thing is high enough confidence
        if (( $CONF > ${THINGLIST[$i2+1]} )); then
          # Set SENDPHOTO to 1
          SENDPHOTO=1
          # Add to caption
          CAPTION+=$LABEL" "$CONF"% "
          # Get rectangle where found thing was found
          Y_MIN=`jq ".predictions[$i].y_min" "$1".json`
          X_MIN=`jq ".predictions[$i].x_min" "$1".json`
          Y_MAX=`jq ".predictions[$i].y_max" "$1".json`
          X_MAX=`jq ".predictions[$i].x_max" "$1".json`

          # Draw box around thing
          convert "$1".bmp -fill none -stroke red -strokewidth 1 -draw "rectangle $X_MIN,$Y_MIN $X_MAX,$Y_MAX" "$1".bmp

          # Figure out where the text will be and draw text background
          X_RECT=`convert -font helvetica -pointsize 18 label:"$LABEL $CONF%" -format %w info:`
          X_RECT=$((X_MIN+X_RECT))
          Y_RECT=$((Y_MIN-16))
          convert "$1".bmp -fill red -stroke red -strokewidth 1 -draw "rectangle $X_MIN,$Y_MIN $X_RECT,$Y_RECT" "$1".bmp

          # Draw text
          convert "$1".bmp -font helvetica -pointsize 18 -draw "text $X_MIN,$Y_MIN '"$LABEL" "$CONF"%'" "$1".bmp
        fi
      fi
    done
  done

  if (( $SENDPHOTO == 1 )); then
    # If previous photo doesn't exist create a generic one
    if [ ! -f "$1"_p.bmp ]; then
      convert -size 100x100 xc:white "$1"_p.bmp
    fi

    # Get difference % from last sent image
    PHOTODIFF=`compare -metric NCC "$1".bmp "$1"_p.bmp null: 2>&1`
    # Convert decimal of sameness to percent of differentness
    PHOTODIFF=$(echo 100-$PHOTODIFF*100 | bc)
    # Make it an int so bash doesn't loose its god damned mind
    PHOTODIFF=`printf "%.0f" "$PHOTODIFF"`

    # Do things if the photo is different enough
    if (( $PHOTODIFF > $9 )); then
      # Remove old previous file
      rm -f "$1"_p.bmp
      # Copy current to new previous file
      cp "$1".bmp "$1"_p.bmp
      # Convert back to jpg
      convert "$1".bmp "$1".jpg

      if (( ${13} == 1 )); then
        # Remove old alert file
        rm -f alerts/$1.jpg
        # Copy alert image to BI
        cp $1.jpg alerts
        # Send alert to BI
        curl "http://192.168.12.6:81/admin?trigger&camera=$1&user=$BIUSER&pw=$BIPW&memo=${CAPTION:${#1}+3}&jpeg=C:\\BlueIris\Alerts\\$1.jpg" > /dev/null 2>&1 &
        # curl "http://192.168.12.6:81/admin?trigger&camera=$1&user=$BIUSER&pw=$BIPW&memo=${CAPTION:${#1}+3}" > /dev/null 2>&1 &
      fi

      if (( ${11} == 1 )); then
        # flowerbed lights
        curl http://192.168.12.197/apps/api/56/devices/105/on?access_token=a64309de-400d-425d-86dc-47c15ef27eed > /dev/null 2>&1 &
      fi

      if (( ${12} == 1 )); then
        # front lights
        curl http://192.168.12.197/apps/api/98/devices/192/on?access_token=2829106d-1c57-4227-a14f-fee19c02a92c > /dev/null 2>&1 &
      fi

      if (( ${10} == 1 )); then
        # Send image to Telegram
        curl -F "caption=$CAPTION" -F "chat_id=$5" -F "photo=@$1.jpg" https://api.telegram.org/bot"$6"/sendphoto > /dev/null 2>&1 &
      fi

      #Sleep on detect
      sleep $8
    fi
  fi

  #Sleep seconds
  sleep $7
}

function loopy {

  # Get config
  . aialert.conf

  # Startup with a random Deepstack AI endpoint
  DSAISERVNUM=$((0 + $RANDOM % ${#DSAISERVERLIST[@]}))

  # Do things until the heat death of the universe.  
  while [ 1 ]
  do
    # Run main function
    aialert $1 $2 $3 $4 $5 $6 $7 $8 $9 ${10} ${11} ${12} ${13}

    # Choose next Deepstack AI endpoint
    DSAISERVNUM=$((DSAISERVNUM+1))

    # Loop to first Deepstack AI endpoint if necessary
    if (( $DSAISERVNUM >= ${#DSAISERVERLIST[@]} )); then
      DSAISERVNUM=0
    fi

    # Get config again.  This lets us change the config while the script is running
    . aialert.conf
  done &
}

# loopy cameraname quality% size% stream chat_id bot_token sleepseconds sleepsecondsondetect percentdifferent telegram_0or1 fblights_0or1 frontlights_0or1 alert_bi_0or1

# $1 cameraname
# $2 quality%
# $3 size% stream chat_id bot_token sleepseconds sleepsecondsondetect percentdifferent telegram_0or1 fblights_0or1 frontlights_0or1 alert_bi_0or1
# $4 stream
# $5 chat_id
# $6 bot_token
# $7 sleepseconds
# $8 sleepsecondsondetect
# $9 percentdifferent
# ${10} telegram_0or1
# ${11} fblights_0or1
# ${12} frontlights_0or1
# ${13} alert_bi_0or1

# example: loopy ipcamd1 100 100 -1 $CCID $TGBOT 2 2 10 1 0 0 1

# Remove old stufffs
rm -f *.jpg
rm -f *.json
rm -f *_p.bmp
rm -f *_m.bmp

#Cabin Creek
loopy ipcamg1 100 100 -1 $CCID $TGBOT 1 30 5 1 0 0 1
loopy ipcamg2 100 100 -1 $CCID $TGBOT 1 30 5 1 0 0 1
loopy ipcamg3 100 100 -1 $CCID $TGBOT 1 30 5 1 0 0 1
loopy ipcambd 100 100 -1 $CCID $TGBOT 1 30 5 1 0 0 1
loopy ipcamsd 100 100 -1 $CCID $TGBOT 1 30 5 1 0 0 1
loopy ipcamd1 100 100 -1 $CCID $TGBOT 1 30 5 1 0 1 1
loopy ipcamfd 100 100 -1 $CCID $TGBOT 1 30 5 1 1 1 1
loopy ipcamlv 100 100 -1 $CCID $TGBOT 1 30 5 0 0 0 1
loopy ipcamsw 100 100 -1 $CCID $TGBOT 1 30 5 1 0 1 1
loopy ipcamsg 100 100 -1 $CCID $TGBOT 1 30 5 1 0 1 1

#Shamrock
loopy DADBY 100 100 -1 $SRID $TGBOT 1 30 5 1 0 0 1
loopy DADDB 100 100 -1 $SRID $TGBOT 1 30 5 1 0 0 1
loopy DADDW 100 100 -1 $SRID $TGBOT 1 30 5 1 0 0 1
loopy DADFD 100 100 -1 $SRID $TGBOT 1 30 5 1 0 0 1


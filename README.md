# ov2-ha-recorder
This repository contains the elements to integrate a high available recorder for [OpenVidu 2](https://openvidu.io). The idea behind the scenes is to store little consecutive pieces of the recording in an external storage compatible with S3, joining them when the recording finish.

This project is a substitute of the recording container provided by default by OpenVidu, but with the advantage of not losing the video already recorded in the event of a server crash.  This is done keeping the chunks in S3 linked to the session name in OpenVidu. So for this recorder all pieces of session with the same name will be handled as the same session.

⚠ __Note__ ⚠:  This recorder requires that your recording is using COMPOSED as your recording output mode. For example, if you are using Java for starting your recording, you have to configure your recording as:
```
RecordingProperties properties = new RecordingProperties.Builder().outputMode(Recording.OutputMode.COMPOSED)
					.build();
Recording recording = openVidu.startRecording(openViduSessionId, properties);
```

## For the impatient
To quickly try this service just do the following: ssh into your OpenVidu server and clone this repository, then execute the replace_recorder.sh that will do:
* Remove the non-HA OpenVidu Docker image
* Pull the new HA recorder for OpenVidu Docker image and tag it as the non-HA one
* Restart your OpenVidu server normally, then the HA recorder image will be used


## HA Recorder
The HA recorder is an image that interfaces with OpenVidu 

### Components 
### Where will be my recordings placed?
### Build the solution
## Q&A
This section addresses common questions about the project.
### Is this project part of the OpenVidu official distribution?
### Is this repository related to the OpenVidu Development Team?
### Do I have to change my OpenVidu server installation?
### Do I need an S3 account?
The package includes a container of 




## Problems detected for Telefónica
For the backendbrowser not integrated with OpenVidu, there are several problems:
* The recorder has to know when the recording has started to start itself, so it has to be connected to the webhook, leaving this unavailable for third parties
  * Additional problem: There is also a recording in OpenVidu, so we are adding another recorder, not replacing one
  * Solution 1, redirect the webhook
  * Solution 2, integrate into OpenViduCE
* The recording never finish, because the ghost page is a perticipant per se, so when all the others particpants left the room it has to detect that is the last one and leave by himself
  * Solution: To check how many participants are in the room, if I am the last one, disconnect me
* The recorder has to know when the status of the recording has changed, so it has to be connected to the webhook, leaving this unavailable for third parties
  * Solution 1, redirect the webhook
  * Solution 2, integrate into OpenViduCE




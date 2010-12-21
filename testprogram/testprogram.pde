/* Test program for rally computer
This test program simulates the output from a gear tooth hall effect switch,  uses a joystick to set the
delay between pulses.

This code is copy right Eric Dinger 2010.
Feel free to use as is or modify to do what you want. Just give credit where credit is due.
*/

#include <math.h>

const byte DEADBAND = 35;

int sensorPin = A0;    // select the input pin for the potentiometer
int iDelayVal = 0;  // variable to store the value coming from the sensor
int iDelta;
byte outPin = 3;
int iCenterVal;
int iCurPulse;

void setup() {
  // declare the ledPin as an OUTPUT:
  Serial.begin(9600);
  pinMode(outPin, OUTPUT);
  iCenterVal = analogRead(sensorPin);
  iCurPulse = 0;
  iDelayVal = 600;
}

void loop() {
  int counter = 0;
  if((counter % 30) == 0)
  {
    iDelta = analogRead(sensorPin) - iCenterVal;    
    Serial.print(iDelta);
    if (iDelayVal > 0 && (iDelta > DEADBAND || iDelta < -DEADBAND))
      // Check if iDelayVal will be less than 0 after the subtaction
      // if it is scale it further or something. Figure logic here later.
      iDelayVal += iDelta/10;
    else if (iDelta > DEADBAND)
      iDelayVal = 1;
    Serial.print(" ");
    Serial.println(iDelayVal);
  }
  counter++;
  
  digitalWrite(outPin, HIGH);
  delay(abs(iDelayVal));      
  digitalWrite(outPin, LOW);
}

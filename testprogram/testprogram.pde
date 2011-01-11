/* Test program for rally computer
This test program simulates the output from a gear tooth hall effect switch,  uses a joystick to set the
delay between pulses.

This code is copy right Eric Dinger 2010.
Feel free to use as is or modify to do what you want. Just give credit where credit is due.
*/

#include <math.h>

const byte DEADBAND = 35;
/*These are user changeable varibles in the rally computer.
*So if these are not the same then the speed displayed on the rally computer 
*will not match the one indicated by the test program.
*/
const float fTireDia = 26.50;
const byte bPpr = 4;
const float fRevsInMile = 63360 / (fTireDia * 3.14);
const int iSampleTime = 200; //5 times a second

int sensorPin = A0;    // select the input pin for the potentiometer
int iDelayVal = 0;  // variable to store the value coming from the sensor
byte outPin = 3;

int iDelta;
int iCenterVal;
int iCurPulse;
float fSpeed = 3;
unsigned long ulPrevious = 0;
unsigned long ulPrevious2 = 0;

int MphToMs(float fSpeed);

void setup() {
  Serial.begin(9600);
  pinMode(outPin, OUTPUT);
  delay(100); //probably unessecery, but let the joystick and a/d settle
  iCenterVal = analogRead(sensorPin);
  iCurPulse = 0;
  iDelayVal = 600;
  Serial.print("Assuming ");
  Serial.print(fTireDia);
  Serial.print(" tire diameter\n with ");
  Serial.print(bPpr, DEC);
  Serial.print(" pulse(s) per revolution\n");
}

void loop() {
  unsigned long ulCurrent = millis();
  if((ulCurrent - ulPrevious) >= iSampleTime)
  {
    iDelta = analogRead(sensorPin) - iCenterVal;    
    Serial.print(iDelta);
    if (fSpeed >= 0 && (iDelta > DEADBAND || iDelta < -DEADBAND))
    {
      // Check if iDelayVal will be less than 0 after the subtaction
      // if it is scale it further or something. Figure logic here later.
      Serial.print("hi");
      fSpeed += iDelta/35;
    }
    else if (fSpeed < 0)
      fSpeed = 0;
    Serial.print(" ");
    Serial.print(fSpeed);
    
    iDelayVal = MphToMs(fSpeed);
    Serial.print(" ");
    Serial.println(iDelayVal);
    ulPrevious = ulCurrent;
  }
  
  ulCurrent = millis();
  digitalWrite(outPin, HIGH);
  
  if (ulCurrent - ulPrevious2 >= iDelayVal)
  {
    digitalWrite(outPin, LOW);
    ulPrevious2 = ulCurrent;
  }
}

int MphToMs(float fSpeed)
{
  return (int)(.25/((fSpeed * fRevsInMile)/3600000));
}
  

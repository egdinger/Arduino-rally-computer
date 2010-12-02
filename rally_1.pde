#include <LiquidCrystal.h>
#include <EEPROM.h>
#include <EEPROM_UTIL.h>
#include <Keypad.h>

//The following structs define the two types of odo's
//that will be used, countUp and countDown
//countUp will count up from 0
struct countUp
{
  long startPulses;
};

//countDown will be the same as countup
//With the addition of the startDistance field
//This will be used as a countdown timer.
struct countDown
{
  long startPulses;
  float startDistance;
};

//Locations of the calibration values in EEPROM
const unsigned PPR_LOC = 0; //pulse per revolutions
const unsigned TIRE_SIZE_LOC = 4; //Tire size stored as a float packed into bytes
const unsigned LPULSECOUNT_LOC = 8; //ulPulseCount is stored here when the unit is turned off, packed into bytes.

//Some conversion values used in the program
const unsigned INCH_IN_MILE = 63360;
const float pi = 3.14;

//Pin values general
const int RESET = 2; //Does need to be on an interupt pin, will rewrite so that it does not!
const int PULSE = 3; //Needs to be on an interupt pin
//Pin values for lcd
const int rs = 4;
const int enable = 5;
const int d4 = 6;
const int d5 = 7;
const int d6 = 8;
const int d7 = 9;
// pin values for matrix keypad
const int D = 18;
const int E = 19;
const int P = 16;
const int Q = 17;
const int M = 14;
const int N = 15;
const int G = 12;
const int F = 13;


const byte ROWS = 4; //four rows
const byte COLS = 4; //three columns
char keys[ROWS][COLS] = {
  {'1','2','3','a'},
  {'4','5','6','b'},
  {'7','8','9','c'},
  {'#','0','*','d'}
};
byte rowPins[ROWS] = {D, E, P, Q}; //connect to the row pinouts of the keypad
byte colPins[COLS] = {M, N, G, F}; //connect to the column pinouts of the keypad

//The odometers available in the rally computer.
//Currently have 1 total distance, this will not be resetable by the reset button
//1 countup, this will be resetable from the reset button
//1 countdown, this will be resetable from the reset button, should this only count down when active?
countUp odoTotal;
countUp odo1;
countDown odo2;

//Various variables
unsigned long ulPulseCount; //The total number of pulses that have occured since the last total reset. I have this as an
// unsigned becuase in this implementation it is an error if ulPulseCount goes negative.
byte bPpr; //The number of pulses per revolution. Since I'm basing this off a sensor that reads the number of lug studs
//This is very unlikely to be greater than 8. But since it may be used with the vehicles existing vss it could be higher.
//64 would not be unlikely when used in this way.
float fDistancePerPulse; //This will be a calculated value.
//float fTire; //Tire diameter, read from the eeprom
float fCirc; //calc'ed
float fTemp; //used as a temp accumulator
byte bCurrentOdo; //Which is the current odo we have selected
byte bPage; //Which is the current lcd data page we want to display
byte bEditMode; //Used to indicate if we want to edit data on the lcd screen
byte bCurSpeed; //I've alrealy forgotten what this was for.
unsigned long ulOldMicros;
unsigned int uiPulseInt;

LiquidCrystal lcd(4, 5, 6, 7, 8, 9);
Keypad keypad = Keypad( makeKeymap(keys), rowPins, colPins, ROWS, COLS );

//Function definitions, look below for more extensive documentation
void pulseHandler();
void resetHandler();
void calDisplay(float fTire);
void saveCalibration();
void updateLED(int odo);
void updateLCD();
float calcCurrentSpeed(long pt);
void buttonHandler(char key);

void setup()
{
  float fTire; //Tire diameter, read from the eeprom
  
  pinMode(RESET, INPUT);
  pinMode(PULSE, INPUT);
  digitalWrite(RESET, HIGH);
  digitalWrite(PULSE, HIGH);
  
  ulPulseCount = 0; //depreciated. Value is stored so it can be persistant across power cycles.
  //EEPROM_readAnything(LPULSECOUNT_LOC, ulPulseCount);
  bCurrentOdo = 1; //Default odo
  bPage = 0;
  fTemp = .00;
  odoTotal.startPulses = ulPulseCount; //Restore total distance
  odo1.startPulses = 0; //reset the odo's, should these also be persistant? Will know after some testing
  odo2.startPulses = 0; //0's may not be the correct value here, may need to be ulPulseCount
  odo2.startDistance = 0;
  ulOldMicros = micros();
  bPpr = EEPROM.read(PPR_LOC); //Get the stored value for ppr
  EEPROM_readAnything(TIRE_SIZE_LOC, fTire); //Get the stored value for the tire size
  
  //Calculate the tire circumfrance and the distance per pulse
  fCirc = fTire * pi;
  fDistancePerPulse = fCirc/bPpr;
  
  digitalWrite(D, HIGH);
  digitalWrite(E, HIGH);
  digitalWrite(P, HIGH);
  digitalWrite(Q, HIGH);
  
  Serial.begin(9600);
  lcd.begin(20,4);
  calDisplay(fTire);
  delay(2000); //Wait two seconds so the user can see the configuration data on the lcd screen
  
  //The following is an idea that may happen, may scrap the wii nunchuck and go with a matrix keypad.
  //Init the wii nunchuck and check to see if the z 
  //button is held down, if so go into the calibration menu
  
  //Attach the interupt handlers. We do this last so no interupts occur while we are setting up the system.
  attachInterrupt(1, pulseHandler, FALLING);
  attachInterrupt(0, resetInterrupt, FALLING);
}

void loop()
{
  int iDisplayCounter = 0;
  char key;
  
  if ((iDisplayCounter % 20) == 0) //Limit the refresh rate of the lcd
  {
    //update the LED
    //updateLED(bCurrentOdo);
    //update the LCD
    updateLCD();
  }
  //check buttons
  key = keypad.getKey();
  
  if (key != NO_KEY){
    buttonHandler(key);
  }

  //get current speed
  //Serial.print(calcCurrentSpeed(uiPulseInt));
  iDisplayCounter++;
}

//Displays the values of the calibration data
//Displays over serial and on the LCD
void calDisplay(float fTire)
{
  //Doing this with serial for now,
  //Later should move to LCD screen
  Serial.print("Tire Diameter: ");
  Serial.println(fTire);
  Serial.print("PPR: ");
  Serial.println(bPpr, DEC);
  lcd.setCursor(0,0);
  //lcd.print("Tire Diameter: ");
  lcd.print(fTire);
  lcd.setCursor(0,1);
  lcd.print(bPpr, DEC);
}

//
void pulseHandler()
{
  unsigned long ulCurrentMicros;
  //ADD DINGER get the time here so we don't have to use pulseIn
  ulCurrentMicros = micros();
  uiPulseInt = ulCurrentMicros - ulOldMicros;
  ulOldMicros = ulCurrentMicros;
  ulPulseCount++;
}

//Resets the current odo
void resetInterrupt()
{
  switch (bCurrentOdo)
  {
    case 1: //ODO1
      odo1.startPulses = ulPulseCount;
      break;
    case 2: //odo 2
      odo2.startPulses = ulPulseCount;
      break;
  }
}

//Resets all of the odo's and the current pulse count.
//Once this has been done it cannot be undone.
void masterReset()
{
  ulPulseCount = 0;
  odo1.startPulses = ulPulseCount;
  odo2.startPulses = ulPulseCount;
  odoTotal.startPulses = ulPulseCount;
  lcd.clear();
  lcd.print("Master reset");
  delay(2000);
}

//This function performs the calculations on the data and
//writes it out to the LED display
void updateLED(int odo)
{
  //Compute the distance traveled
  float distance = 0.0; //((ulPulseCount/bPpr) * fTire) / INCH_IN_MILE;
  int tPulseCount;
  switch (odo)
  {
    case 0:
      tPulseCount = (ulPulseCount - odoTotal.startPulses);
      distance = (tPulseCount * fDistancePerPulse) / INCH_IN_MILE;
      break;
    case 1:
      //Count up
      tPulseCount = (ulPulseCount - odo1.startPulses);
      distance = (tPulseCount * fDistancePerPulse) / INCH_IN_MILE;
      break;
    case 2:
      //Count down
      tPulseCount = (ulPulseCount - odo2.startPulses);
      distance = odo2.startDistance - (tPulseCount * fDistancePerPulse) / INCH_IN_MILE;
      break;
  }

  Serial.print(ulPulseCount);
  Serial.print(" ");
  Serial.println(distance, 2);
}

//Prints less important data to the lcd
void updateLCD()
{
  //what should be on the lcd it will be a 16x2
  //123456789ABCDEF
  //ODO DOWN   
  //  1 43.44 
  //ODO will list the number of the selected odo or DWN or total
  //Up will show the last selected count down value
  switch(bPage)
  {
    case 0:
      lcd.setCursor(0,0);
      lcd.print("ODO TOT:");
      lcd.setCursor(9,0);
      lcd.print((ulPulseCount - odoTotal.startPulses) * fDistancePerPulse / INCH_IN_MILE);
      lcd.setCursor(0,1);
      lcd.print("ODO   1:");
      lcd.setCursor(9,1);
      lcd.print(ulPulseCount - odo1.startPulses);
      lcd.setCursor(0,2);
      lcd.print("ODO  UP:");
      if (bEditMode)
      {
        lcd.setCursor(8,2);
        lcd.print("^");
        lcd.print(fTemp);
      }
      else
      {
        lcd.setCursor(9,2);
        lcd.print(odo2.startDistance);
      }
      break;
    case 1:
      lcd.setCursor(0,0);
      lcd.print("page1");
      break;
    case 2:
      lcd.setCursor(0,0);
      lcd.print("1: Configuration");
      lcd.setCursor(0,1);
      lcd.print("2: Master Reset");
      if (bEditMode)
      {
        lcd.setCursor(0,2);
        lcd.print("^");
      }
      break;
  }
  /*switch (bCurrentOdo)
  {
    case 0: //Total Milage
      lcd.print("TOT");
      break;
    case 1: //first count up odo
      lcd.print("  1");
      break;
    case 2: //first count down odo
      lcd.print("DWN");
      break;
  }
  lcd.setCursor(4,1);
  //Should be in a switch statement, but since we only have 1 count up it doesn't matter yet.
  lcd.print(odo2.startDistance);*/
  lcd.setCursor(0,3);
  lcd.print(calcCurrentSpeed(uiPulseInt),2);
}

//Calculates the current speed with pulse time given in microseconds
//returns speed in mph
float calcCurrentSpeed(long pt)
{
  //5681.81 is a magic number
  //It is the conversion factor from inches/uSec to mph
  return ((20.8/pt)*5681.81);
}

void calibrateMenu()
{
  bool control = true;
  lcd.setCursor(0,0);
  lcd.print("PPR  Tire Dia");
  lcd.setCursor(0,1);
  while (control)
  {
    lcd.print(bPpr);
    //get nunchuck data
    //if nunchuck x is up increment bPpr
    //if z is pushed switch to tire size
    //if nunchuck x is up halfway increment fTire by .1
    //if nunchuck x is greater than halfway up
    //increment fTire by 1.0
    //delay by something, 50?
    //if other nunchuck button is pressed, 
    //control = false;
  }
  saveCalibration();
}

//Uses prompts to get data from the user and then
//saves it to eeprom
//Currently does not get anything from user
void saveCalibration()
{
  EEPROM.write(PPR_LOC, bPpr);
  //EEPROM_writeAnything(TIRE_SIZE_LOC, fTire);
}

void buttonHandler(char key)
{
  switch (key)
  {
    case '1':
      if(bPage == 0 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .01;     
      }
      break;
    case '2':
      if(bPage == 0 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .02;
      }
      if(bPage == 2 && bEditMode == true)
      {
        masterReset();
        bEditMode = !bEditMode;
      }
      break;
    case '3':
      if(bPage == 0 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .03;
      }
      break;
    case '4':
      if(bPage == 0 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .04;
      }
      break;
    case '5':
      if(bPage == 0 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .05;
      }
      break;
    case '6':
      if(bPage == 0 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .06;
      }
      break;
    case '7':
      if(bPage == 0 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .07;
      }
      break;
    case '8':
      if(bPage == 0 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .08;
      }
      break;
    case '9':
      if(bPage == 0 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .09;
      }
      break;
    case '0':
      if(bPage == 0 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .00;
      }
      break;
    case 'a':
      //Can't change pages when you are editing
      if(!bEditMode)
      {
        bPage = (bPage + 1) % 3;
        lcd.clear();
      }
      break;
    case 'b':
    case 'c':
    case 'd':
      break;
    case '#':
      //enter edit mode
      if(bEditMode)
      {
        //We are in edit mode so clear any unsaved value
        fTemp = 0;
      }
      bEditMode = !bEditMode;
      lcd.clear();
      break;
    case '*':
      //Commit change
      if(bEditMode)
      {
        if(bPage == 0)
          {
            odo2.startDistance = fTemp;
            fTemp = 0;
          }
         //exit edit mode
         bEditMode = !bEditMode;
         lcd.clear();
      }
      break;
  }
}

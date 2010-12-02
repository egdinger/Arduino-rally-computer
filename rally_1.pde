#include <LiquidCrystal.h>
#include <EEPROM.h>
#include <EEPROM_UTIL.h>
#include <Keypad.h>

enum { i = 1, f};
//The following structs define the two types of odo's
//that will be used, countUp and countDown
//countUp will count up from 0
struct countUp
{
  unsigned long startPulses;
};

//countDown will be the same as countup
//With the addition of the startDistance field
//This will be used as a countdown timer.
struct countDown
{
  unsigned long startPulses;
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
const int PULSE = 3; //Needs to be on an interupt pin
//Pin values for lcd
const int rs = 4;
const int enable = 5;
const int d4 = 6;
const int d5 = 7;
const int d6 = 8;
const int d7 = 9;
// pin values for matrix keypad
//These are named funny because thats what they are labeled on the keypad
//I'm using a greyhill 87BB3-201
const int D = 18;
const int E = 19;
const int P = 16;
const int Q = 17;
const int M = 14;
const int N = 15;const int G = 12;
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
volatile unsigned long ulPulseCount; //The total number of pulses that have occured since the last total reset. I have this as an
// unsigned becuase in this implementation it is an error if ulPulseCount goes negative.
byte bPpr; //The number of pulses per revolution. Since I'm basing this off a sensor that reads the number of lug studs
//This is very unlikely to be greater than 8. But since it may be used with the vehicles existing vss it could be higher.
//64 would not be unlikely when used in this way.
float fDistancePerPulse; //This will be a calculated value.
//float fTire; //Tire diameter, read from the eeprom
float fCirc; //calc'ed
float fTemp; //used as a temp accumulator
byte bTemp; //used as a temp accumlator
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
//void resetHandler();
void calDisplay(float fTire);
void saveCalibration();
void updateLED(int odo);
void updateLCD();
int calcCurrentSpeed(long pt);
void buttonHandler(char key);

void setup()
{
  float fTire; //Tire diameter, read from the eeprom
  
  pinMode(PULSE, INPUT);
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
}

void loop()
{
  int iDisplayCounter = 0;
  char key;
  
  if ((iDisplayCounter % 30) == 0) //Limit the refresh rate of the lcd
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
  //Doing this with serial and lcd
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
void resetCurrentOdo()
{
  Serial.println("in reset");
  switch (bCurrentOdo)
  {
    case 0:
      //Not resetable here
      break;
    case 1: //ODO1
      cli();
      Serial.println(odo1.startPulses, DEC);
      odo1.startPulses = ulPulseCount;
      Serial.println(odo1.startPulses, DEC);
      sei();
      break;
    case 2: //odo 2
      cli();
      odo2.startPulses = ulPulseCount;
      sei();
      break;
  }
}

//Resets all of the odo's and the current pulse count.
//Once this has been done it cannot be undone.
void masterReset()
{
  cli();
  ulPulseCount = 0;
  odo1.startPulses = ulPulseCount;
  odo2.startPulses = ulPulseCount;
  odoTotal.startPulses = ulPulseCount;
  lcd.clear();
  lcd.print("Master reset");
  sei();
  delay(2000);
}

//This function performs the calculations on the data and
//writes it out to the LED display
void updateLED(int odo)
{
  //Compute the distance traveled
  float distance;
  int tPulseCount;
  switch (odo)
  {
    case 0:
      distance = ((ulPulseCount - odoTotal.startPulses) * fDistancePerPulse) / INCH_IN_MILE;
      break;
    case 1:
      //Count up
      distance = ((ulPulseCount - odoTotal.startPulses) * fDistancePerPulse) / INCH_IN_MILE;
      break;
    case 2:
      //Count down
      distance = odo2.startDistance - ((ulPulseCount - odoTotal.startPulses) * fDistancePerPulse) / INCH_IN_MILE;
      break;
  }
}

//Prints less important data to the lcd
void updateLCD()
{
  cli();
  unsigned long ulTempCount = ulPulseCount;
  sei();
  
  //Using a 20x4 lcd will look something like
  //Page 0
  //ODO TOT: xxx.xx
  //ODO   1: xx.xx
  //ODO DWN: xx.xx
  //XXX
  //Page 1
  //Unsure
  //Page 2
  //1: Configuration
  //2: Master Reset
  //3: Don't know if these will be useful
  //4: Ditto
  switch(bPage)
  {
    case 0:
      //The first page will display all of the available odo's and some information about them
      //Not sure if I want to display the count or what we want to count down from for count down
      lcd.setCursor(0,0);
      lcd.print("ODO TOT:");
      lcd.setCursor(9,0);
      lcd.print((ulPulseCount - odoTotal.startPulses) * fDistancePerPulse / INCH_IN_MILE);
      lcd.setCursor(0,1);
      lcd.print("ODO   1:");
      lcd.setCursor(9,1);
      lcd.print(((ulTempCount - odo1.startPulses) * fDistancePerPulse / INCH_IN_MILE));
      lcd.setCursor(0,2);
      lcd.print("ODO DWN:");
      if (bEditMode)
      {
        lcd.setCursor(8,2);
        lcd.print("^");
        lcd.print(fTemp);
      }
      else
      {
        lcd.setCursor(9,2);
        //Do I want to count down here, or only on the led?
        //        lcd.print(odo2.startDistance);
        lcd.print(odo2.startDistance - ((ulTempCount - odo2.startPulses) * fDistancePerPulse / INCH_IN_MILE));
      }
      break;
    case 1:
      lcd.setCursor(0,0);
      lcd.print("Debug Stuff:");
      lcd.setCursor(0,1);
      lcd.print(ulPulseCount);
      lcd.setCursor(0,2);
      lcd.print("Selected ODO:");
      lcd.setCursor(14,2);
      lcd.print(bCurrentOdo, DEC);
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
    case 3:
      //The calibration menu
      lcd.setCursor(0,0);
      lcd.print("Pulses per rev:");
      lcd.setCursor(15,0);
      if(bEditMode == i)
      {
        lcd.print("^");
        lcd.print(bTemp, DEC);
      }
      else
      {
        lcd.print(bPpr, DEC);
      }
      
      lcd.setCursor(0,1);
      lcd.print("Tire diameter:");
      lcd.setCursor(14,1);
      if(bEditMode == f)
      {
        lcd.print("^");
        lcd.print(fTemp);
      }
      else
      {
        //lcd.print(fTire);
      }
      break;
  }
  //Do I want to display the current speed here all the time?
  lcd.setCursor(0,3);
  lcd.print(calcCurrentSpeed(uiPulseInt), DEC);
}

//Calculates the current speed with pulse time given in microseconds
//returns speed in mph
int calcCurrentSpeed(long pt)
{
  //56818.1 is a magic number
  //It is the conversion factor from inches/uSec to mph
  //20.8 is tire circumfrance / ppr
  //should calc this!
  return ((20.8/pt)*56818.1);
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
      if(bPage == 0 || bPage == 4 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .01;     
      }
      if(bPage == 2 && bEditMode == true)
      {
        bPage = 3;
        bEditMode = false;//!bEditMode;
        lcd.clear();
        Serial.println("In here");
      }
      break;
    case '2':
      if(bPage == 0 || bPage == 4 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .02;
      }
      if(bPage == 2 && bEditMode == true)
      {
        masterReset();
        bEditMode = false;//!bEditMode;
      }
      break;
    case '3':
      if(bPage == 0 || bPage == 4 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .03;
      }
      break;
    case '4':
      if(bPage == 0 || bPage == 4 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .04;
      }
      break;
    case '5':
      if(bPage == 0 || bPage == 4 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .05;
      }
      break;
    case '6':
      if(bPage == 0 || bPage == 4 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .06;
      }
      break;
    case '7':
      if(bPage == 0 || bPage == 4 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .07;
      }
      break;
    case '8':
      if(bPage == 0 || bPage == 4 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .08;
      }
      break;
    case '9':
      if(bPage == 0 || bPage == 4 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .09;
      }
      break;
    case '0':
      if(bPage == 0 || bPage == 4 && bEditMode == true)
      {
        fTemp = fTemp * 10 + .00;
      }
      break;
    case 'a':
      //Can't change pages when you are editing
      if(bEditMode && bPage == 3)
      {
        bEditMode = (++bEditMode % 2) + 1;
        lcd.clear();
      }
      else
      {
        bPage = (bPage + 1) % 3;
        lcd.clear();
      }
      break;
    case 'b':
      //swap the current/active odometer
      //This means the one displayed on the LED display also the one affected by reset
      bCurrentOdo = (++bCurrentOdo % 3);
      break;
    case 'c':
    case 'd':
      resetCurrentOdo();
      break;
    case '#':
      //enter edit mode

      if(bPage == 0 && bEditMode)
      {
        odo2.startDistance = fTemp;
        fTemp = 0;
      }
      if(bPage == 0 && bEditMode == f)
      {
        //odo2.startDistance = fTemp;
        fTemp = 0;
      }
      if(bPage == 0 && bEditMode == i)
      {
        bPpr = bTemp;
        bTemp = 0;
      }
      bEditMode = !bEditMode;
      lcd.clear();
      break;
    case '*':
      //Commit change
      if(bEditMode)
      {
         //We are in edit mode so clear any unsaved value
         fTemp = 0;
         bTemp = 0;
         //exit edit mode
         bEditMode = !bEditMode;
         lcd.clear();
      }
      break;
  }
}

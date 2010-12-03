#include <LiquidCrystal.h>
#include <EEPROM.h>
#include <EEPROM_UTIL.h>
#include <Keypad.h>

#define MPH

//used to let us know what data field we want to edit 
enum { i, f};
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
//Locations of the data of the odo's this is so they can be persistant. That is exist across powercycles.
const unsigned ODO_TOT_START_PULSES_LOC = 12;
const unsigned ODO_1_START_PULSES_LOC = 16;
const unsigned ODO_DWN_START_PULSES_LOC = 20;
const unsigned ODO_DWN_START_DISTANCE_LOC = 24;
const unsigned UL_PULSE_COUNT_LOC = 28;

//Some conversion values used in the program
#ifdef MPH
  #define DISTANCE_CONVERSION_FACTOR 63360 //Inches in a mile
  #define PULSE_TIME_TO_SPEED 56818.1 //Conversion factor. Inches per uSec to MPH
#endif
#ifdef KPH
  #define DISTANCE_CONVERSION_FACTOR 1000 //m in a Km
  #define PULSE_TIME_TO_SPEED 2 //junk values so I'll know if I'm here FIX need to calculate this
#endif
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
float fTire; //Tire diameter, read from the eeprom
float fCirc; //calc'ed
float fTemp; //used as a temp accumulator
byte bTemp; //used as a temp accumlator
byte bCurrentOdo; //Which is the current odo we have selected
byte bPage; //Which is the current lcd data page we want to display
byte bEditMode; //Used to indicate if we want to edit data on the lcd screen
byte bEditWhat; //Used to indicate what we want to edit, if there is more than 1 editable field on the page
byte bCurSpeed; //I've alrealy forgotten what this was for.
volatile unsigned long ulOldMicros;
volatile unsigned int uiPulseInt;

LiquidCrystal lcd(4, 5, 6, 7, 8, 9);
Keypad keypad = Keypad( makeKeymap(keys), rowPins, colPins, ROWS, COLS );

//Function definitions, look below for more extensive documentation
void pulseHandler();
//void resetHandler();
void calDisplay();
void saveCalibration();
void updateLED(int odo);
void updateLCD();
int calcCurrentSpeed(long pt);
void buttonHandler(char key);
void shutdownHandler();
void getPersitantData();

void setup()
{  
  pinMode(PULSE, INPUT);
  digitalWrite(PULSE, HIGH);
  Serial.begin(9600);
  
  bCurrentOdo = 1; //Default odo
  bPage = 0;
  fTemp = .00;
  getPersitantData();
  ulOldMicros = micros();
  
  //Calculate the tire circumfrance and the distance per pulse
  fCirc = fTire * pi;
  fDistancePerPulse = fCirc/bPpr;
  
  digitalWrite(D, HIGH);
  digitalWrite(E, HIGH);
  digitalWrite(P, HIGH);
  digitalWrite(Q, HIGH);
  
  lcd.begin(20,4);
  calDisplay();
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
void calDisplay()
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
  sei();
  odo1.startPulses = ulPulseCount;
  odo2.startPulses = ulPulseCount;
  odoTotal.startPulses = ulPulseCount;
  lcd.clear();
  lcd.print("Master reset");
  delay(2000);
  lcd.clear();
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
      distance = ((ulPulseCount - odoTotal.startPulses) * fDistancePerPulse) / DISTANCE_CONVERSION_FACTOR;
      break;
    case 1:
      //Count up
      distance = ((ulPulseCount - odoTotal.startPulses) * fDistancePerPulse) / DISTANCE_CONVERSION_FACTOR;
      break;
    case 2:
      //Count down
      distance = odo2.startDistance - ((ulPulseCount - odoTotal.startPulses) * fDistancePerPulse) / DISTANCE_CONVERSION_FACTOR;
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
  //3: Shutdown
  //4: Ditto
  switch(bPage)
  {
    case 0:
      //The first page will display all of the available odo's and some information about them
      //Not sure if I want to display the count or what we want to count down from for count down
      lcd.setCursor(0,0);
      lcd.print("ODO TOT:");
      lcd.setCursor(9,0);
      lcd.print((ulPulseCount - odoTotal.startPulses) * fDistancePerPulse / DISTANCE_CONVERSION_FACTOR);
      lcd.setCursor(0,1);
      lcd.print("ODO   1:");
      lcd.setCursor(9,1);
      lcd.print(((ulTempCount - odo1.startPulses) * fDistancePerPulse / DISTANCE_CONVERSION_FACTOR));
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
        lcd.print(odo2.startDistance - ((ulTempCount - odo2.startPulses) * fDistancePerPulse / DISTANCE_CONVERSION_FACTOR));
      }
      lcd.setCursor(13, bCurrentOdo);
      lcd.print("@");
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
      lcd.setCursor(1,0);
      lcd.print("1: Configuration");
      lcd.setCursor(1,1);
      lcd.print("2: Master Reset");
      lcd.setCursor(1,2);
      lcd.print("3: Shutdown");
      if (bEditMode)
      {
        lcd.setCursor(0,1);
        lcd.print("^");
      }
      break;
    case 3:
      //The calibration menu
      lcd.setCursor(0,0);
      lcd.print("Pulses per rev:");
      lcd.setCursor(15,0);
      if(bEditWhat == i && bEditMode)
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
      if(bEditWhat == f && bEditMode)
      {
        lcd.print("^");
        lcd.print(fTemp);
      }
      else
      {
        lcd.print(fTire);
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
  return ((fDistancePerPulse/pt)*PULSE_TIME_TO_SPEED);
}

//Uses prompts to get data from the user and then
//saves it to eeprom
//Currently does not get anything from user
void saveCalibration()
{
  EEPROM.write(PPR_LOC, bPpr);
  EEPROM_writeAnything(TIRE_SIZE_LOC, fTire);
  lcd.clear();
  lcd.print("Calibration saved");
  delay(1000);
  lcd.clear();
}

void buttonHandler(char key)
{
  switch (key)
  {
    case '1':
      if(bPage == 0 || bPage == 3 && bEditMode == true)
      {
        if(bEditWhat == f)
        {
          fTemp = fTemp * 10 + .01; 
        }
        if(bEditWhat == i)
        {
          bTemp = bTemp * 10 + 1;   
        }
      }
      if(bPage == 2 && bEditMode == true)
      {
        bPage = 3;
        bEditMode = !bEditMode;
        lcd.clear();
      }
      break;
    case '2':
      if(bPage == 0 || bPage == 3 && bEditMode == true)
      {
        if(bEditWhat == f)
        {
          fTemp = fTemp * 10 + .02;
        }
        if(bEditWhat == i)
        {
          bTemp = bTemp * 10 + 2;
        }
      }
      if(bPage == 2 && bEditMode == true)
      {
        masterReset();
        bEditMode = false;//!bEditMode;
      }
      break;
    case '3':
      if(bPage == 0 || bPage == 3 && bEditMode == true)
      {
        if(bEditWhat == f)
        {
          fTemp = fTemp * 10 + .03;
        }
        if(bEditWhat == i)
        {
          bTemp = bTemp * 10 + 3;
        }
      }
      if(bPage == 2 && bEditMode == true)
      {
        shutdownHandler();
        bEditMode = false;//!bEditMode;
      }
      break;
    case '4':
      if(bPage == 0 || bPage == 3 && bEditMode == true)
      {
        if(bEditWhat == f)
        {
          fTemp = fTemp * 10 + .04;
        }
        if(bEditWhat == i)
        {
          bTemp = bTemp * 10 + 4;
        }
      }
      break;
    case '5':
      if(bPage == 0 || bPage == 3 && bEditMode == true)
      {
        if(bEditWhat == f)
        {
          fTemp = fTemp * 10 + .05;
        }
        if(bEditWhat == i)
        {
          bTemp = bTemp * 10 + 5;
        }
      }
      break;
    case '6':
      if(bPage == 0 || bPage == 3 && bEditMode == true)
      {
        if(bEditWhat == f)
        {
          fTemp = fTemp * 10 + .06;
        }
        if(bEditWhat == i)
        {
          bTemp = bTemp * 10 + 6;
        }
      }
      break;
    case '7':
      if(bPage == 0 || bPage == 3 && bEditMode == true)
      {
        if(bEditWhat == f)
        {
          fTemp = fTemp * 10 + .07;
        }
        if(bEditWhat == i)
        {
          bTemp = bTemp * 10 + 7;
        }
      }
      break;
    case '8':
      if(bPage == 0 || bPage == 3 && bEditMode == true)
      {
        if(bEditWhat == f)
        {
          fTemp = fTemp * 10 + .08;
        }
        if(bEditWhat == i)
        {
          bTemp = bTemp * 10 + 8;
        }
      }
      break;
    case '9':
      if(bPage == 0 || bPage == 3 && bEditMode == true)
      {
        if(bEditWhat == f)
        {
          fTemp = fTemp * 10 + .09;
        }
        if(bEditWhat == i)
        {
          bTemp = bTemp * 10 + 9;
        }
      }
      break;
    case '0':
      if(bPage == 0 || bPage == 3 && bEditMode == true)
      {
        if(bEditWhat == f)
        {
          fTemp = fTemp * 10 + .00;
        }
        if(bEditWhat == i)
        {
          bTemp = bTemp * 10 + 0;
        }
      }
      break;
    case 'a':
      //if we are in edit mode
      if(bEditMode)
      {
        if(bPage == 3)
        {
          bEditWhat = bEditWhat == i ? f : i;
          lcd.clear();
          Serial.print("bEditWhat is now ");
          Serial.println(bEditWhat, DEC);
        }
      }
      else //Can't change pages when you are editing
      {
        bPage = (bPage + 1) % 3;
        lcd.clear();
      }
      break;
    case 'b':
      //swap the current/active odometer
      //This means the one displayed on the LED display also the one affected by reset
      bCurrentOdo = (++bCurrentOdo % 3);
      lcd.clear();
      break;
    case 'c':
      if(bPage == 3 && bEditMode)
      {
        saveCalibration();
        bEditMode = !bEditMode;
        bEditWhat = f;
      }
      break;
    case 'd':
      resetCurrentOdo();
      break;
    case '#':
      //enter edit mode

      if(bPage == 0 && bEditMode)
      {
        odo2.startDistance = fTemp;
      }
      if(bPage == 3 && bEditMode)
      {
        if(bEditWhat == i)
        {
          bPpr = bTemp;
        }
        if(bEditWhat == f)
        {
          fTire = fTemp;
        }
      }
      bTemp = 0;
      fTemp = 0;
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

//This function should be called before we loose power to save the state of
//the odo's so they can be recalled
void shutdownHandler()
{
  //Save the current ulPulseCount and odo statuses
  EEPROM_writeAnything(UL_PULSE_COUNT_LOC, ulPulseCount);
  EEPROM_writeAnything(ODO_TOT_START_PULSES_LOC, odoTotal.startPulses);
  EEPROM_writeAnything(ODO_1_START_PULSES_LOC, odo1.startPulses);
  EEPROM_writeAnything(ODO_DWN_START_PULSES_LOC, odo2.startPulses);
  EEPROM_writeAnything(ODO_DWN_START_DISTANCE_LOC, odo2.startDistance);
  
  //This is temporary untill I figure out more about the power supply, ie can I shut it off remotely, etc
  lcd.clear();
  lcd.print("Safe to shutdown");
  while(true);
}

//This function will be called when the device first starts and
//after we update any of the configurable persistant data
void getPersitantData()
{
  bPpr = EEPROM.read(PPR_LOC); //Get the stored value for ppr
  EEPROM_readAnything(TIRE_SIZE_LOC, fTire); //Get the stored value for the tire size
  EEPROM_readAnything(UL_PULSE_COUNT_LOC, ulPulseCount);
  EEPROM_readAnything(ODO_TOT_START_PULSES_LOC, odoTotal.startPulses);
  EEPROM_readAnything(ODO_1_START_PULSES_LOC, odo1.startPulses);
  EEPROM_readAnything(ODO_DWN_START_PULSES_LOC, odo2.startPulses);
  EEPROM_readAnything(ODO_DWN_START_DISTANCE_LOC, odo2.startDistance);
}

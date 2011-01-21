/*
Unit test program for rally computer

This code is copy right Eric Dinger 2010.
Feel free to use as is or modify to do what you want. Just give credit where credit is due.
*/

/*These are user changeable varibles in the rally computer.
*So if these are not the same then the speed displayed on the rally computer 
*will not match the one indicated by the test program.
*/
const float fTireDia = 26.50;
const byte bPpr = 4;
const float fRevsInMile = 63360 / (fTireDia * 3.14);

byte outPin = 3;

int MphToMs(float fSpeed)
{
  return (int)(.25/((fSpeed * fRevsInMile)/3600000));
}

void Test(int iSpeed, int iPulses)
{
  int iDelayVal = MphToMs(iSpeed);
  digitalWrite(outPin, HIGH);
  for(int i = 0; i < iPulses; i++)
  {
    digitalWrite(outPin, LOW);
    delay(iDelayVal);
    digitalWrite(outPin, HIGH);
  }
}
  

void setup() {
  Serial.begin(9600);
  pinMode(outPin, OUTPUT);
  Serial.print("Assuming ");
  Serial.print(fTireDia);
  Serial.print(" tire diameter\n with ");
  Serial.print(bPpr, DEC);
  Serial.print(" pulse(s) per revolution\n");
  Serial.println("Unit test application follow onscreen directions");
  Serial.println("Go to the debug screen");
  delay(5000);
  
  //First test is 5mph for 50 pulses
  Serial.println("5 mph");
  Test(5, 50);
  Serial.println("You should have 50 pulses");
  delay(5000);
  
  Serial.println("15 mph");
  Test(15, 50);
  Serial.println("You should have 100 pulses");
  delay(5000);
  
  Serial.println("30 mph");
  Test(30, 100);
  Serial.println("You should have 200 pulses");
  delay(5000);
  
  Serial.println("60 mph");
  Test(60, 200);
  Serial.println("You should have 400 pulses");
  delay(5000);
  
  Serial.println("120 mph");
  Test(120, 200);
  Serial.println("You should have 600 pulses");
  delay(5000);
  
  Serial.println("150 mph");
  Test(150, 200);
  Serial.println("You should have 800 pulses");
  delay(5000);
  
  Serial.println("150 mph - play with menus");
  Test(150, 4000);
  Serial.println("You should have 4800 pulses");
  delay(5000);
  
  Serial.println("300 mph");
  Test(300, 4000);
  Serial.println("You should have 8800 pulses");
  delay(5000);
}

void loop()
{
}

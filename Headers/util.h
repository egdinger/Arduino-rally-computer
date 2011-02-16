//used to let us know what data field we want to edit 
enum { i, f};

//This enum will define better names for menu pages
enum {odo, option, calibration, debug, raw};
//The following classes define the two types of odo's
//that will be used, countUp and countDown
//countUp will count up from 0
class countUp
{
  public:
  unsigned long startPulses;
  float calcDistance(unsigned long ulCount);
};

//countDown will be the same as countup
//With the addition of the startDistance field
//This will be used as a countdown timer.
class countDown: public countUp
{
  public:
  float startDistance;
  float calcDistanceLeft(unsigned long ulCount);
};
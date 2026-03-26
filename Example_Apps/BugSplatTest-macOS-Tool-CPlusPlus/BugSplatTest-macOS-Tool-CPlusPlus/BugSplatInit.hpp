//
//  BugSplatInit.hpp
//  BugSplatTest-macOS-Tool-CPlusPlus
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#ifndef BugSplatInit_hpp
#define BugSplatInit_hpp

#include <iostream>
#include <stdio.h>

int bugSplatInit(const char * bugSplatDatabase);
int bugSplatSetAttributeValue(std::string attribute, std::string value);
int bugSplatSendFeedback(std::string title, std::string description);
void mainObjCRunLoop();

#endif /* BugSplatInit_hpp */

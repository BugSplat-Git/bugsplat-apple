//
//  main.cpp
//  BugSplatTest-macOS-Tool-CPlusPlus
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

#include <chrono>
#include <iostream>
#include "BugSplatInit.hpp"

int setAttributeAndValue()
{
    std::string attribute, value;
    std::cout << "Enter attribute and value separated by a space:\n";
    std::cin >> attribute >> value;

    std::cout << "setAttributeAndValue called with: ";
    std::cout << attribute << "\n";
    std::cout << value << "\n";

    return bugSplatSetAttributeValue(attribute, value);
}

int sendFeedback()
{
    std::string title, description;
    std::cout << "Enter feedback title: ";
    std::getline(std::cin, title);
    std::cout << "Enter feedback description: ";
    std::getline(std::cin, description);

    return bugSplatSendFeedback(title, description);
}

int checkInput(std::string input)
{
    std::cout << "checkInput called: " << input << std::endl;

    if (input == "seg fault")
    {
        std::cout << "Triggering segfault..." << std::endl;
        // Use volatile to prevent compiler optimization
        volatile int *ptr = nullptr;
        *ptr = 42;  // Write to null pointer - guaranteed crash
    }
    else if (input == "divide by zero")
    {
        std::cout << "Triggering divide by zero..." << std::endl;
        volatile int a = 10;
        volatile int b = 0;
        std::cout << "Result: " << a / b << std::endl;  // Division by zero
    }
    else if (input == "set")
    {
        return setAttributeAndValue();
    }
    else if (input == "feedback")
    {
        return sendFeedback();
    }
    else if (input == "hang")
    {
        std::cout << "Simulating a 4-second main-thread hang. Kill the process with Ctrl+C or a SIGKILL to see a fatal-hang report uploaded on next run." << std::endl;
        auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(4);
        while (std::chrono::steady_clock::now() < deadline) { }
        std::cout << "Hang window ended (main thread recovered)." << std::endl;
    }
    else
    {
        std::cout << "Unknown command. Try: 'seg fault', 'divide by zero', 'set', 'feedback', 'hang', or 'q' to quit" << std::endl;
    }

    return 0;
}

int getUserInput() {
    std::string input;

    std::cout << "Enter text (enter 'q' to quit):\n";
    std::getline(std::cin, input);
    if (input == "q")
    {
        return -1;
    }

    return checkInput(input);
}

int main(int argc, const char * argv[]) {
    std::cout << "Welcome to BugSplat C++ Example!\n";

    char databaseName[20];
    strcpy(databaseName, "fred");

    bugSplatInit(databaseName);

    std::string input;

    while (true) {

        mainObjCRunLoop();

        std::cout << "\nEnter text (enter 'q' to quit):\n";
        std::getline(std::cin, input);
        if (input == "q")
        {
            break;
        }

        checkInput(input);
    }

    return 0;
}


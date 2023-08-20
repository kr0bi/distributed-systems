#!/usr/bin/env python3

import json

class Config:

    def __init__(self, url):
        with open(url, "r") as file:
            self.conf_dict = json.load(file)

    def get_key(self, key):
        return self.conf_dict[key]

    def set_key(self, key, attr):
        self.conf_dict[key].append(attr)

    def del_entry(self, hKey, wKey):
        index = 0
        for item in self.get_key("orari"):
            #check if both elems are correct
            if item == hKey and self.conf_dict["grammi"][index] == wKey :
                break
            index = index + 1
        #delete elems from dict
        del self.conf_dict["orari"][index]
        del self.conf_dict["grammi"][index]

        #update json
        with open("scheduler.json", "w") as file:
            json.dump(self.conf_dict, file)

    def dictZip(self):
        orari = self.get_key("orari")
        wgts = self.get_key("grammi")
        return list(zip(orari, wgts))

    def sortJson(self):
        #sorts json data
        zipped = self.dictZip()
        ziplist = sorted(zipped, key=lambda tup: (tup[0]))
        new_dict = {"orari": [], "grammi": [] }
        for item in ziplist:
                new_dict["orari"].append(item[0])
                new_dict["grammi"].append(item[1])
        self.conf_dict = new_dict
        #updates global variable

    def set_entry(self, schedule, weight):
        self.set_key("orari", schedule)
        self.set_key("grammi", weight)
        self.sortJson()
        with open("scheduler.json", "w") as file:
            json.dump(self.conf_dict, file)

if __name__ == "__main__":
    data = Config("scheduler.json")
    while True:
        a = input("set key: ")
        b = input("set attr: ")
        print(data.get_key(a))
        data.set_key(a, b)
        print(data.get_key(a))
        with open("scheduler.json", "w") as file:
            json.dump(data.conf_dict, file)

    
    

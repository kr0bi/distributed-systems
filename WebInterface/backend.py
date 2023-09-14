#!/usr/bin/env python3

import networkx as nx
from io import BytesIO
import matplotlib.pyplot as plt
from pyvis.network import Network
from flask import Flask, render_template, jsonify, request, send_file
from xml.dom.minidom import parse, parseString
import os.path
import xml


class Backend:

    ### Initializes backend object
    # dout = HX711 dt pin, pd_sck = HX711 sck pin, servo_pin = servo motor GPIO pin 
    def __init__(self):
        self.net = Network()

    def getGraphFromFile(self):
        path = os.path.dirname(os.path.dirname(__file__)) + '/erlang/graph.xml'
        edgeList = []
        edgeCostList = []
        nodeList = []
        #print(path)
        try:
            document = parse(path)
            nodes = document.getElementsByTagName("client")
            #print(nodes)

            for node in nodes:
                nodeList.append(int(node.firstChild.nodeValue))
            edges = document.getElementsByTagName("route")
            
            for edge in edges:
                wEdge = (int(edge.childNodes[0].firstChild.nodeValue), int(edge.childNodes[1].firstChild.nodeValue))
                edgeCostList.append(int(edge.childNodes[2].firstChild.nodeValue))
                edgeList.append(wEdge)
        except xml.parsers.expat.ExpatError:
            pass
        #print(nodeList)
        #print(edgeList)
        return nodeList, edgeList, edgeCostList
    
    def getPathFromFile(self):
        path = os.path.dirname(os.path.dirname(__file__)) + '/erlang/path.xml'
        #print(path)
        costList = []
        pathList = []
        nodeList = []
        bestCost = 1000000
        counter = 0
        bestPath = 0
        
        try :
            document = parse(path)
            nodes = document.getElementsByTagName("path")
            for node in nodes:
                nodeList = []
                for client in node.childNodes:
                    if client == node.lastChild:
                        Cost = int(client.firstChild.nodeValue)
                        costList.append(Cost)
                    else:
                        nodeList.append(int(client.firstChild.nodeValue))
                pathList.append(nodeList)
                counter = counter + 1
            for i in range(len(costList)):
                if ((costList[i] < bestCost) and 
                    ((pathList[i].sort() == pathList[len(pathList)-1].sort()) and 
                     (len(pathList[i]) == len(pathList[len(pathList)-1])) )):
                    #print("Path {} and last path {}".format(pathList[i], pathList[len(pathList)-1]))
                    #print("Results are {} and {}".format((costList[i] < bestCost), (pathList[i].sort() == pathList[len(pathList)-1].sort())))
                    bestPath = i
                    bestCost = costList[i]
        except xml.parsers.expat.ExpatError:
            pass
        return pathList, costList, bestPath
    

        
    def addNodes(self, Nodes):
        self.net.add_nodes(Nodes, title=list(map(addClientTitle, Nodes)))

    def addEdges(self, Edges, Costs):
        for i in range(len(Edges)):
            self.net.add_edge(Edges[i][0], Edges[i][1], title = Costs[i], width = 3)

    def resetGraph(self):
        self.net = Network()


    def drawGraph(self):
        self.net.toggle_physics(True)
        self.net.write_html(os.path.dirname(__file__) + '/templates/graph.html', local=True, notebook=False, open_browser=False)

    def addNode(self, id):
        self.net.add_node(id, label=id, value=200)
        self.net.add_edge(1, id, weight=id)

    def drawBestPath(self, Path, Cost):
        for i in range(len(Path)):
            if i == len(Path) - 1:
                self.net.add_edge(Path[i], Path[0], color='#b22222', title ="Path cost: {}".format(Cost), width = 4)
            else:
                self.net.add_edge(Path[i], Path[i+1], color='#b22222', title ="Path cost: {}".format(Cost), width = 4)

    def getNodes(self):
        self.net.get_nodes()
    
    def getEdges(self):
        self.net.get_edges()

    def isDifferent(self, Nodes, Edges):
        return (self.net.get_nodes() != Nodes) or (self.net.get_edges() != Edges) 

def addClientTitle(node):
        return "Client {}".format(node)


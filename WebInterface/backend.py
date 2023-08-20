#!/usr/bin/env python3

import networkx as nx
from io import BytesIO
import matplotlib.pyplot as plt
from pyvis.network import Network
from flask import Flask, render_template, jsonify, request, send_file


class Backend:

    ### Initializes backend object
    # dout = HX711 dt pin, pd_sck = HX711 sck pin, servo_pin = servo motor GPIO pin 
    def __init__(self):
        print("Setup started")
        self.net = Network()
        #self.graph = nx.Graph()
        self.net.add_nodes([1,2,3], value=[10, 100, 400],
                         title=['I am node 1', 'node 2 here', 'and im node 3'],
                         x=[21.4, 54.2, 11.2],
                         y=[100.2, 23.54, 32.1],
                         label=['NODE 1', 'NODE 2', 'NODE 3'],
                         color=['#00ff1e', '#162347', '#dd4b39'])
        self.net.add_edge(1,2, weight=0.8)
        self.net.add_edge(1,3, weight=0.3)
        print("Setup finished")   


    def drawGraph(self):
        self.net.toggle_physics(True)
        self.net.write_html("./WebInterface/images/graph.html", local=True, notebook=False, open_browser=False)
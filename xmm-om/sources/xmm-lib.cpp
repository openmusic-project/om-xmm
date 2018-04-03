//
//  xmm-lib.cpp
//  xmm
//
//  Created by Paul Best on 12/03/2018.
//


#include "include-xmm.h"
#include "stdlib.h"
#include "xmm-lib.hpp"
//#include <xmmTrainingSet.hpp>
#include <iostream>
#include <sstream>
#include <string>

std::string toString(char c){
    std::stringstream ss;
    std::string target;
    ss << c;
    ss >> target;
    return target;
}


void* initXMM(){
    static xmm::HierarchicalHMM *mhhmm = new xmm::HierarchicalHMM(false);
    return mhhmm;
}


void* initDataset(int numcolumns){
    static xmm::TrainingSet *mdataset = new xmm::TrainingSet(xmm::MemoryMode::OwnMemory, xmm::Multimodality::Unimodal);
    mdataset->dimension=numcolumns;
    mdataset->column_names.resize(numcolumns);
    const std::vector<std::string> vec(numcolumns, "col");
    mdataset->column_names.set(vec);
    return mdataset;
}



int fillDataset(void* descptr, int sample_num, void* sample_sizes, void* labls, void* dataset){
    //init variables from pointers
    const float*** descr = static_cast<const float***>(descptr);
    const int* sizes = static_cast<const int*>(sample_sizes);
    const char* labels = static_cast<char*>(labls);
    xmm::TrainingSet* mdataset = static_cast<xmm::TrainingSet*>(dataset);
    std::vector<float> &observation = *new std::vector<float>(mdataset->dimension.get());
    try{
        mdataset->empty();
        //For each sample
        for(int j=0; j<sample_num; j++){
            //Build Phrase
            mdataset->addPhrase(j, toString(labels[j]));
            mdataset->getPhrase(j)->column_names.resize(mdataset->column_names.size());
            mdataset->getPhrase(j)->column_names = mdataset->column_names.get();
            mdataset->getPhrase(j)->dimension =mdataset->column_names.size();
            for(int it =0; it < sizes[j]; it++){
                //Add each sound descriptor to the phrase
                for(int i =0; i<mdataset->dimension.get(); i++){
                    observation[i] = descr[j][i][it];
                }
                mdataset->getPhrase(j)->record(observation);
            }
        }
    }catch ( const std::exception & Exp )
    {
        std::cerr << "\nErreur fillDataset : " << Exp.what() << ".\n";
    }
    delete &observation;
    return int('Y');
}



int trainXMM(void* dataset, void* model){
    try{
        xmm::HierarchicalHMM *mhhmm = static_cast<xmm::HierarchicalHMM*>(model);
        xmm::TrainingSet *mdataset = static_cast<xmm::TrainingSet*>(dataset);
        mhhmm->train(mdataset);
    }catch ( const std::exception & Exp )
    {
        std::cerr << "\nErreur train : " << Exp.what() << ".\n";
    }
    return int('Y');
}



int runXMM(void* descptr, int sample_size, int columnnum, void* model){
    xmm::HierarchicalHMM* mhhmm = static_cast<xmm::HierarchicalHMM*>(model);
    const float** descr = static_cast<const float**>(descptr);
    std::vector<float> &observation = *new std::vector<float>(columnnum);
    mhhmm->reset();
    for(int k=0; k<sample_size;k++){
        for(int i =0; i<columnnum; i++){
            observation[i] = descr[i][k];
        }
        mhhmm->filter(observation);
    }
    delete &observation;
    return mhhmm->results.likeliest[0];
}


int save_model_JSON(char* pathptr, void* model){
    xmm::HierarchicalHMM* mhhmm = static_cast<xmm::HierarchicalHMM*>(model);
    const char* path = static_cast<const char*>(pathptr);
    
    std::ofstream file_id;
    file_id.open(path);
    Json::FastWriter writer;
    file_id << writer.write(mhhmm->toJson());
    file_id.close();
    return 'Y';
}

void* importJson(char* pathptr, void* modelptr){
    const char* path = static_cast<const char*>(pathptr);
    xmm::HierarchicalHMM* mhhmm = static_cast<xmm::HierarchicalHMM*>(modelptr);
    std::ifstream file(path, std::ifstream::binary);
    Json::Value json;
    file>>json;
    static char* labls = (char*)malloc((mhhmm->models.size()+1)*sizeof(char));
    try{
        mhhmm->fromJson(json);
        int i =0;
        for(auto it = mhhmm->models.begin(); it!=mhhmm->models.end();it++){
            labls[i]=it->first[0];
            i++;
        }
        labls[i]='0';
    }catch(const std::exception & Exp )
    {
        std::cerr << "\nErreur import : " << Exp.what() << ".\n";
    }
    return labls;
}

void free_model(void* model, void* dataset){
    try{
        if(dataset){
            free (dataset);
            std::cout<<"dataset freed"<<std::endl;
        }
        if(model){
            free(model);
            std::cout<<"model freed"<<std::endl;
        }
    }catch(const std::exception & Exp )
    {
        std::cerr << "\nErreur free : " << Exp.what() << ".\n";
    }
}
           
           
           
           

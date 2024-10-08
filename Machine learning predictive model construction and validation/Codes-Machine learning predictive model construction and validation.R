####113 machine learning####
work.path <- "D://CeRNA结直肠癌//诊断模型//113种机器学习算法诊断PredictiveML_3.0"; setwd(work.path) 
code.path <- file.path(work.path, "Codes")
data.path <- file.path(work.path, "InputData")
res.path <- file.path(work.path, "Results")
fig.path <- file.path(work.path, "Figures")

library(openxlsx)
library(seqinr)
library(plyr)
library(randomForestSRC)
library(glmnet)
library(plsRglm)
library(gbm)
library(caret)
library(mboost)
library(e1071)
library(BART)
library(MASS)
library(snowfall)
library(xgboost)
library(ComplexHeatmap)
library(RColorBrewer)
library(pROC)

source(file.path(code.path, "ML.R"))
FinalModel <- c("panML", "multiLogistic")[2]

# Training Cohort ---------------------------------------------------------
Train_expr <- read.table(file.path(data.path, "trainexp.txt"), header = T, sep = "\t", row.names = 1,check.names = F,stringsAsFactors = F)
Train_class <- read.table(file.path(data.path, "traincli.txt"), header = T, sep = "\t", row.names = 1,check.names = F,stringsAsFactors = F)
Train_class$outcome=ifelse(Train_class$outcome =='H','1','0')
Train_class$outcome<-as.numeric(Train_class$outcome)
comsam <- intersect(rownames(Train_class), colnames(Train_expr))
Train_expr <- Train_expr[,comsam]; Train_class <- Train_class[comsam,,drop = F]

## Validation Cohort -------------------------------------------------------
Test_expr <- read.table(file.path(data.path, "模型exptest - 副本.txt"), header = T, sep = "\t", row.names = 1,check.names = F,stringsAsFactors = F)
Test_class <- read.table(file.path(data.path, "模型clitest - 副本.txt"), header = T, sep = "\t", row.names = 1,check.names = F,stringsAsFactors = F)
Test_class$outcome=ifelse(Test_class$outcome =='H','1','0')
Test_class$outcome<-as.numeric(Test_class$outcome)
comsam <- intersect(rownames(Test_class), colnames(Test_expr))
Test_expr <- Test_expr[,comsam]; Test_class <- Test_class[comsam,,drop = F]
comgene <- intersect(rownames(Train_expr),rownames(Test_expr))
Train_expr <- t(Train_expr[comgene,]) 
Test_expr <- t(Test_expr[comgene,]) 
Train_set = scaleData(data = Train_expr, centerFlags = T, scaleFlags = T) 
names(x = split(as.data.frame(Test_expr), f = Test_class$Cohort)) 
Test_set = scaleData(data = Test_expr, cohort = Test_class$Cohort, centerFlags = T, scaleFlags = T)
summary(apply(Train_set, 2, var))
summary(apply(Test_set, 2, var))
methods <- read.xlsx(file.path(code.path, "methods.xlsx"), startRow = 2)
methods <- methods$Model
methods <- gsub("-| ", "", methods)

## Train the model --------------------------------------------------------
classVar = "outcome" 
min.selected.var = 2 
## Pre-training
Variable = colnames(Train_set)
preTrain.method =  strsplit(methods, "\\+")
preTrain.method = lapply(preTrain.method, function(x) rev(x)[-1]) 
preTrain.method = unique(unlist(preTrain.method)) 

preTrain.var <- list()

for (method in preTrain.method){
  preTrain.var[[method]] = RunML(method = method, 
                                 Train_set = Train_set, 
                                 Train_label = Train_class, 
                                 mode = "Variable",      
                                 classVar = classVar) 
}
preTrain.var[["simple"]] <- colnames(Train_set)
## Model training
model <- list()

Train_set_bk = Train_set 
cat(match(method, methods), ":", method, "\n")
method_name = method 
method <- strsplit(method, "\\+")[[1]] 

if (length(method) == 1) method <- c("simple", method)

Variable = preTrain.var[[method[1]]] 
Train_set = Train_set_bk[, Variable]  
Train_label = Train_class            
model[[method_name]] <- RunML(method = method[2],       
                              Train_set = Train_set,    
                              Train_label = Train_label,
                              mode = "Model",            
                              classVar = classVar)      

if(length(ExtractVar(model[[method_name]])) <= min.selected.var) {
  model[[method_name]] <- NULL
}
}
Train_set = Train_set_bk; rm(Train_set_bk) 
saveRDS(model, file.path(res.path, "modelLXQ.rds"))

if (FinalModel == "multiLogistic"){
  logisticmodel <- lapply(model, function(fit){ 
    tmp <- glm(formula = Train_class[[classVar]] ~ .,
               family = "binomial", 
               data = as.data.frame(Train_set[, ExtractVar(fit)]))
    tmp$subFeature <- ExtractVar(fit) 
    return(tmp)
  })
}
saveRDS(logisticmodel, file.path(res.path, "logisticmodelLXQ.rds")) 

## Evaluate the model -----------------------------------------------------


model <- readRDS(file.path(res.path, "modelLXQ.rds"))
methodsValid <- names(model)

RS_list <- list()
for (method in methodsValid){
  # method<-"RF+LDA"
  RS_list[[method]] <- CalPredictScore(fit = model[[method]], 
                                       new_data = rbind.data.frame(Train_set,Test_set)) 
}
RS_mat <- as.data.frame(t(do.call(rbind, RS_list)))
write.table(RS_mat, file.path(res.path, "RS_matLXQ.txt"),sep = "\t", row.names = T, col.names = NA, quote = F) # 输出风险评分文件


Class_list <- list()
for (method in methodsValid){
  Class_list[[method]] <- PredictClass(fit = model[[method]], 
                                       new_data = rbind.data.frame(Train_set,Test_set)) 
}
Class_mat <- as.data.frame(t(do.call(rbind, Class_list)))
#Class_mat <- cbind.data.frame(Test_class, Class_mat[rownames(Class_mat),]) 
write.table(Class_mat, file.path(res.path, "Class_matLXQ.txt"), 
            sep = "\t", row.names = T, col.names = NA, quote = F)


fea_list <- list()
for (method in methodsValid) {
  fea_list[[method]] <- ExtractVar(model[[method]])
}


fea_df <- lapply(model, function(fit){
  data.frame(ExtractVar(fit))
})
fea_df <- do.call(rbind, fea_df)
fea_df$algorithm <- gsub("(.+)\\.(.+$)", "\\1", rownames(fea_df))
colnames(fea_df)[1] <- "features"
write.table(fea_df, file.path(res.path, "fea_dfLXQ.txt"), #
            sep = "\t", row.names = F, col.names = T, quote = F)



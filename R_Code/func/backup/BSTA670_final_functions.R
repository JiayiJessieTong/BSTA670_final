######### Function 1: expit ########
## Input: x
## Output: expit(x)
expit = function(x){exp(x)/(1+exp(x))}
##### ------------------------ #####


######### Function 2: likelihood function ########
## Input: X, n*p matrix (n: total number of patients, p: dimension of covariates) 
##        Y, n*1 binary vector (1 indicates case and 0 indicates control)
##        beta, p*1 vector (coefficients of the covariates)
## Output: log-likelihood value
Lik = function(beta,X,Y){
  design = cbind(1,X)
  sum(Y*(design%*%t(t(beta)))-log(1+exp(design%*%t(t(beta)))))/length(Y)
}
##### ------------------------------------ #####


######### Function 3: 1st order gradient of log-likelihood ########
## Input: X, n*p matrix (n: total number of patients. p: dimension of covariates) 
##        Y, n*1 binary vector (1 indicates case and 0 indicates control)
##        beta, p*1 vector (coefficients of the covariates)
## Output: 1st order gradient of log-likelihood
Lgradient = function(beta,X,Y){
  design = cbind(1,X)
  t(Y-expit(design%*%t(t(beta))))%*%design/length(Y)
}
##### ------------------------------------ #####


######### Function 4: 2nd order gradient of log-likelihood ########
## Input: X, n*p matrix (n: total number of patients. p: dimension of covariates) 
##        beta, p*1 vector (coefficients of the covariates)
## Output: 2nd order gradient of log-likelihood
Lgradient2 =function(beta,X){
  design = cbind(1,X)
  Z=expit(design%*%beta)
  t(c(-1*Z*(1-Z))*design)%*%design/nrow(X)
}
##### ------------------------------------ #####


######### Function 5: meat of the sandwich variance estimator ########
## Input: X, n*p matrix (n: total number of patients. p: dimension of covariates) 
## Output: meat of the sandwich variance estimator 
Lgradient_meat = function(beta,X,Y){
  design = cbind(1,X)
  Z = expit(design%*%beta)
  t(c(Y-Z)*design)%*%(c(Y-Z)*design)/nrow(X)
}
##### ------------------------------------ #####


######### Function 7: data generator ########
## Input: beta, p*1 vector (coefficients of the covariates)
##        N, total number of observations
## Output: surrogate likelihood value
data_generator <-  function(N,beta,K,n)
{
  X1 = rnorm(N)         
  X2 = runif(N,0,1) 
  X3 = rbinom(N,1,0.35) 
  X4 = rbinom(N,1,0.6)     
  X = cbind(1,X1,X2,X3,X4)
  meanY = expit(X%*%beta)
  Y = rbinom(N,1,meanY)
  data = data.frame(cbind(X1,X2,X3,X4,Y))
  # add hospital ID
  if (length(n) == 1){
    data$ID = rep(1:K, each = n)
  }else{
    data$ID = rep(1:K, n)
  }
  
  return(data)
}
##### ------------------------------------ #####



######### Function 8: sandwich var est ########
## Input:  beta, X, Y, N
## Output: sandwich variance estimate of est_ODAL
Sandwich <- function(beta,X,Y,N){
  mat_L1 = Lgradient_meat(beta,X,Y)
  mat_L2 = Lgradient2(beta,X)
  inv_L2 = solve.default(mat_L2)
  out = inv_L2%*%mat_L1%*%inv_L2/N
  return(out)
}
##### ------------------------------------ #####



######### Function 9: main_ODAL function ########
## Input: Data, N*(ID + Y + p covariates)
## Output: MSE of pooled, ODAL, and local estimators
main_run_ODAL <-function(Data, beta_true){
  
  N = dim(Data)[1]
  p = dim(Data)[2]- 2
  K = length(unique(Data$ID))
  
  ########### METHOD 1: pooled analysis ##############
  # overall data
  X = as.matrix(Data[,-c(5,6)])
  Y = Data$Y
  
  # pooled beta and var
  fit_pooled = summary(glm(Y~X, family = "binomial"(link = "logit")))
  est_pooled = fit_pooled$coefficients[,1]
  sd_pooled = fit_pooled$coefficients[,2]
  var_pooled =sd_pooled^2
  ##### ------------------------------------ #####
  
  ########### METHOD 2: local analysis ##############
  # extract the local data. Treat ID = 1 as local site
  local_ind = which(Data$ID == 1)
  local_data = Data[local_ind,]
  Xlocal = as.matrix(local_data[,-c(5,6)])
  Ylocal = local_data$Y
  
  # Local beta and var
  fit_local = summary(glm(Ylocal~Xlocal, family = "binomial"(link = "logit")))
  est_local = fit_local$coefficients[,1]
  sd_local = fit_local$coefficients[,2]
  var_local = sd_local^2
  ##### ------------------------------------ #####
  
  ########### METHOD 3: ODAL method ##############
  
  ######### Function 6: surrogate likelihood function ########
  ## Input: beta, p*1 vector (coefficients of the covariates)
  ##       Xlocal: local covariates
  ##       Ylocal: local outcome
  ## Output: surrogate likelihood value
  SL = function(beta){
    -Lik(beta,Xlocal,Ylocal) - L%*%beta
  }
  ##### ------------------------------------ #####
  
  ## meta initial value
  # sub_est = sub_var = matrix(0, ncol = length(beta_true), nrow = K)
  # for (i in 1:K){
  #   sub_data = Data[which(Data$ID == i),]
  #   sub_Y = sub_data$Y
  #   sub_X = as.matrix(sub_data[,-c(5,6)])
  #   sub_fit = summary(glm(Y~X, family = "binomial"(link = "logit")))
  #   sub_est[i,] = sub_fit$coefficients[,1]
  #   sub_var[i,] =  sub_fit$coefficients[,2]^2
  # }
  # init = apply(sub_est/sub_var,2,function(x){sum(x, na.rm = T)})/apply(1/sub_var,2,function(x){sum(x, na.rm = T)})
  #   
  # use local point estimate as initial value
  L = Lgradient(est_local,X,Y)
  
  # ODAL point estimate
  est_ODAL = optim(est_local,SL,control = list(maxit = 10000,reltol = 1e-10))$par
  
  # var of the estimator
  cov_ODAL = Sandwich(est_ODAL,Xlocal,Ylocal,N)
  var_ODAL = diag(cov_ODAL)
  ##### ------------------------------------ #####
  
  bias_pooled = (est_pooled - beta_true)^2
  MSE_pooled = bias_pooled + var_pooled
  
  bias_local = (est_local - beta_true)^2
  MSE_local = bias_local + var_local
  
  bias_ODAL = (est_ODAL - beta_true)^2
  MSE_ODAL = bias_ODAL + var_ODAL
  
  
  return(list(MSE_pooled = MSE_pooled,
              MSE_local = MSE_local,
              MSE_ODAL = MSE_ODAL))
}
##### ------------------------------------ #####




######### Function 10: heterogeneous data generator ########
## This is the function to generate heterogeneous data (i.e.
## different prevalence/intercept term)
## Note: assume no heterogenous of the covariates 
## Input: beta, p*1 vector (coefficients of the covariates)
##        N, total number of observations
## Output: surrogate likelihood value
data_generator_hetero <-  function(N,beta,K,n)
{
  
  
  # prevalence median
  pre_med = beta[1]
  pre_list = pre_med + runif(K,-2,0)

  meanY = X1 = X2 = X3 = X4 = rep(NA, N)
  for (i in 1:K){
    ind = seq((i-1)*n + 1, i*n, by = 1)
    X1[ind] = rnorm(n)         
    X2[ind] = runif(n,0,1) 
    X3[ind] = rbinom(n,1,0.35) 
    X4[ind] = rbinom(n,1,0.6)     
    X_tmp = cbind(1,X1[ind],X2[ind],X3[ind],X4[ind])
    meanY[ind] = expit(X_tmp%*%c(pre_list[i], beta[-1]))
  }
   
  Y = rbinom(N,1,meanY)
  data = data.frame(cbind(X1,X2,X3,X4,Y))
  # add hospital ID
  data$ID = rep(1:K, each = n)
  
  return(data)
}
##### ------------------------------------ #####




######### Function 11: main_ODAL hetero function ########
## add the conditional regression model as the gold standard
## Input: Data, N*(ID + Y + p covariates)
## Output: MSE of pooled, ODAL, and local estimators
main_run_ODAL_hetero <-function(Data, beta_true){
  
  N = dim(Data)[1]
  p = dim(Data)[2]- 2
  K = length(unique(Data$ID))
  
  ########### METHOD 0: pooled analysis (naive) ##############
  # overall data
  X = as.matrix(Data[,-c(5,6)])
  Y = Data$Y
  
  # pooled beta and var
  fit_pooled = summary(glm(Y~X, family = "binomial"(link = "logit")))
  est_pooled = fit_pooled$coefficients[,1]
  sd_pooled = fit_pooled$coefficients[,2]
  var_pooled =sd_pooled^2
  ##### ------------------------------------ #####
  
  ########### METHOD 1: pooled analysis (clogit) ##############
  # pooled beta and var
  fit_clogit = summary(clogit(Y~X + strata(Data$ID)), method = "exact")
  est_clogit = fit_clogit$coefficients[,1]
  sd_clogit = fit_clogit$coefficients[,2]
  var_clogit =sd_clogit^2
  ##### ------------------------------------ #####
  
  ########### METHOD 2: local analysis ##############
  # extract the local data. Treat ID = 1 as local site
  local_ind = which(Data$ID == 1)
  local_data = Data[local_ind,]
  Xlocal = as.matrix(local_data[,-c(5,6)])
  Ylocal = local_data$Y
  
  # Local beta and var
  fit_local = summary(glm(Ylocal~Xlocal, family = "binomial"(link = "logit")))
  est_local = fit_local$coefficients[,1]
  sd_local = fit_local$coefficients[,2]
  var_local = sd_local^2
  ##### ------------------------------------ #####
  
  ########### METHOD 3: ODAL method ##############
  
  ######### Function 6: surrogate likelihood function ########
  ## Input: beta, p*1 vector (coefficients of the covariates)
  ##       Xlocal: local covariates
  ##       Ylocal: local outcome
  ## Output: surrogate likelihood value
  SL = function(beta){
    -Lik(beta,Xlocal,Ylocal) - L%*%beta
  }
  ##### ------------------------------------ #####
  
  # use local point estimate as initial value
  L = Lgradient(est_local,X,Y)
  
  # ODAL point estimate
  est_ODAL = optim(est_local,SL,control = list(maxit = 10000,reltol = 1e-10))$par
  
  # var of the estimator
  cov_ODAL = Sandwich(est_ODAL,Xlocal,Ylocal,N)
  var_ODAL = diag(cov_ODAL)
  ##### ------------------------------------ #####
  
  bias_pooled = (est_pooled - beta_true)^2
  MSE_pooled = bias_pooled + var_pooled
  
  bias_clogit = (est_pooled_clogit - beta_true[-1])^2
  MSE_clogit = bias_clogit + var_clogit
  
  bias_local = (est_local - beta_true)^2
  MSE_local = bias_local + var_local
  
  bias_ODAL = (est_ODAL - beta_true)^2
  MSE_ODAL = bias_ODAL + var_ODAL
  
  
  return(list(MSE_pooled = bias_pooled,
              MSE_clogit = bias_clogit,
              MSE_local = bias_local,
              MSE_ODAL = bias_ODAL))
}
##### ------------------------------------ #####



